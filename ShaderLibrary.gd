extends RefCounted
## ShaderLibrary.gd -- TATOOL recipe registry + per-pass shader assembler (first-build skeleton)
##
## TAG FORMAT: a comment after a uniform line, fields separated by |
##   uniform float u_segments = 6.0; // @label Slides | @min 1 | @max 32 | @sens 1
##   @label    text shown in the menus
##   @min/@max allowed range (used for clamping and to derive a fallback sensitivity)
##   @sens     recommended sensitivity (Tier 5 "recommended" row)
##   @channels comma list overriding the default channel names (X,Y / R,G,B,A)
##   @global   shared by the whole pass: declared once, value survives formula changes
##
## RECIPE CONVENTIONS (function must be named fx_<id>; helper functions should start with <id>_):
##   Pass 1 (pattern):  vec4 fx_<id>(vec2 uv)   single-select
##   Pass 2 (warp):     vec2 fx_<id>(vec2 uv)   stackable, chained in the order added
##   Pass 3 (filter):   vec4 fx_<id>(vec2 uv)   single-select for now, may sample u_warped_texture
## Recipes may read u_time. Never declare samplers or u_time; the assembler adds them.
## Supported uniform types for now: float, vec2, vec4 (vec4 is treated as a Color).

const PASS_PATTERN: int = 0
const PASS_WARP: int = 1
const PASS_FILTER: int = 2

# id -> recipe dictionary. Insertion order is the menu order.
var recipes: Dictionary = {}

var _re_uniform: RegEx


func _init() -> void:
	_re_uniform = RegEx.new()
	# groups: 1 type, 2 name, 3 hint (e.g. source_color), 4 default literal, 5 comment tags
	_re_uniform.compile("^\\s*uniform\\s+(float|vec2|vec4)\\s+(\\w+)\\s*(?::\\s*([^=;]+?))?\\s*=\\s*([^;]+);\\s*(?://(.*))?$")
	_register_builtin_recipes()


# =========================================================================
# REGISTRY
# =========================================================================
func _register(id: String, pass_index: int, display_name: String, source: String, stackable: bool) -> void:
	recipes[id] = {
		"id": id,
		"pass": pass_index,
		"name": display_name,
		"source": source,
		"stackable": stackable,
	}

## Recipes for one pass, in menu order (Tier 2 rows).
func recipes_for_pass(pass_index: int) -> Array:
	var out: Array = []
	for id in recipes:
		if recipes[id]["pass"] == pass_index:
			out.append(recipes[id])
	return out

func is_stackable(id: String) -> bool:
	return recipes.has(id) and recipes[id]["stackable"]

## Debug helper for testing long-list scrolling: adds N harmless Pass 2 recipes.
func add_dummy_recipes(count: int) -> void:
	for i in range(count):
		var id: String = "dummy_%02d" % (i + 1)
		var src: String = "uniform float u_amount = 0.5; // @label Amount | @min 0 | @max 1 | @sens 0.05\n"
		src += "vec2 fx_%s(vec2 uv) {\n" % id
		src += "\treturn uv + vec2(sin(uv.y * 10.0 + u_time), 0.0) * u_amount * 0.02;\n"
		src += "}\n"
		_register(id, PASS_WARP, "TEST FORMULA %02d" % (i + 1), src, true)


# =========================================================================
# ASSEMBLER: active recipe ids (in stacking order) -> one shader for the pass
# Returns {"code": String, "uniforms": Array of uniform records}
# =========================================================================
func assemble_pass(pass_index: int, active_ids: Array) -> Dictionary:
	var decl_lines: PackedStringArray = PackedStringArray()
	var func_blocks: PackedStringArray = PackedStringArray()
	var records: Array = []
	var seen_globals: Dictionary = {}
	var used_ids: Array = []

	# 1) pass-level globals that belong to the pass itself (always present)
	for line in _template_globals(pass_index).split("\n"):
		var trec: Dictionary = _parse_uniform_line(line, "")
		if trec.is_empty():
			continue
		trec["is_global"] = true
		seen_globals[trec["base_name"]] = true
		records.append(trec)
		decl_lines.append(_decl_line(trec))

	# 2) active recipes, in the order they were added
	for id in active_ids:
		if not recipes.has(id):
			continue
		used_ids.append(id)
		var renames: Dictionary = {}
		var body: PackedStringArray = PackedStringArray()
		for line in String(recipes[id]["source"]).split("\n"):
			var rec: Dictionary = _parse_uniform_line(line, id)
			if rec.is_empty():
				body.append(line)
				continue
			if rec["is_global"]:
				if seen_globals.has(rec["base_name"]):
					continue # already declared for this pass; share that one
				seen_globals[rec["base_name"]] = true
			else:
				# formula-specific: prefix with the recipe id so stacked formulas never collide
				rec["name"] = "u_%s_%s" % [id, String(rec["base_name"]).trim_prefix("u_")]
				renames[rec["base_name"]] = rec["name"]
			records.append(rec)
			decl_lines.append(_decl_line(rec))
		var body_text: String = "\n".join(body)
		for base in renames:
			body_text = _rename_word(body_text, base, renames[base])
		func_blocks.append(body_text)

	var code: String = "shader_type canvas_item;\n"
	code += _pass_header(pass_index) + "\n"
	code += "\n".join(decl_lines) + "\n\n"
	code += "\n".join(func_blocks) + "\n\n"
	code += _pass_fragment(pass_index, used_ids)
	return {"code": code, "uniforms": records}


func _pass_header(pass_index: int) -> String:
	match pass_index:
		PASS_PATTERN:
			return "uniform float u_time;"
		PASS_WARP:
			return "uniform sampler2D u_pattern_texture : filter_linear;\nuniform float u_time;"
	return "uniform sampler2D u_warped_texture : filter_linear;\nuniform float u_time;"


# Uniforms owned by the pass itself (shown under Tier 2 > GLOBALS). Tag format as above.
func _template_globals(pass_index: int) -> String:
	match pass_index:
		PASS_PATTERN:
			var g1: String = "uniform float u_global_zoom = 1.0; // @label Master Pattern Scale | @min 0.2 | @max 5.0 | @sens 0.05 | @global\n"
			g1 += "uniform vec2 u_global_offset = vec2(0.0, 0.0); // @label Master Pan | @min -2.0 | @max 2.0 | @sens 0.01 | @global\n"
			g1 += "uniform float u_rotation_speed = 0.0; // @label Rotation Speed | @min -2 | @max 2 | @sens 0.05 | @global"
			return g1
		PASS_WARP:
			var g2: String = "uniform float u_warp_master_mix = 1.0; // @label Warp Dry/Wet Mix | @min 0.0 | @max 1.0 | @sens 0.01 | @global\n"
			g2 += "uniform float u_global_speed_mod = 1.0; // @label Master Animation Speed | @min 0.0 | @max 3.0 | @sens 0.05 | @global"
			return g2
		PASS_FILTER:
			var g3: String = "uniform float u_master_brightness = 1.0; // @label Master Brightness | @min 0.5 | @max 2.0 | @sens 0.02 | @global\n"
			g3 += "uniform float u_master_saturation = 1.0; // @label Master Saturation | @min 0.0 | @max 2.0 | @sens 0.02 | @global\n"
			g3 += "uniform float u_master_rotation = 0.0; // @label Master Canvas Spin | @min -3.1416 | @max 3.1416 | @sens 0.05 | @global"
			return g3
	return ""

func _pass_fragment(pass_index: int, ids: Array) -> String:
	var f: String = ""
	match pass_index:
		PASS_PATTERN:
			f += "void fragment() {\n"
			f += "\t// Apply universal Pan and Zoom globals to space first\n"
			f += "\tvec2 uv = (UV - 0.5) * u_global_zoom + u_global_offset;\n"
			f += "\tfloat ang = u_time * u_rotation_speed;\n"
			f += "\tuv = vec2(cos(ang) * uv.x - sin(ang) * uv.y, sin(ang) * uv.x + cos(ang) * uv.y) + 0.5;\n"
			if ids.is_empty():
				f += "\tCOLOR = vec4(0.0, 0.0, 0.0, 1.0);\n"
			else:
				f += "\tCOLOR = fx_%s(uv);\n" % ids[0]
			f += "}\n"
			
		PASS_WARP:
			f += "vec2 tatool_mirror(vec2 x) {\n"
			f += "\treturn abs(mod(x + 1.0, 2.0) - 1.0);\n"
			f += "}\n\n"
			f += "void fragment() {\n"
			f += "\tvec2 original_uv = UV;\n"
			f += "\tvec2 uv = UV;\n"
			for id in ids:
				f += "\tuv = fx_%s(uv);\n" % id
			f += "\t// Globally blend between unwarped and warped space based on Dry/Wet knob\n"
			f += "\tvec2 final_uv = mix(original_uv, uv, u_warp_master_mix);\n"
			f += "\tCOLOR = texture(u_pattern_texture, tatool_mirror(final_uv));\n"
			f += "}\n"
			
		PASS_FILTER, _:
			f += "void fragment() {\n"
			f += "\t// Universal Master Rotation for the entire incoming viewport\n"
			f += "\tvec2 rotated_uv = UV - 0.5;\n"
			f += "\tfloat master_ang = u_master_rotation;\n"
			f += "\trotated_uv = vec2(cos(master_ang) * rotated_uv.x - sin(master_ang) * rotated_uv.y, sin(master_ang) * rotated_uv.x + cos(master_ang) * rotated_uv.y) + 0.5;\n"
			f += "\t\n"
			f += "\tvec4 scene_color;\n"
			if ids.is_empty():
				f += "\tscene_color = texture(u_warped_texture, rotated_uv);\n"
			else:
				f += "\tscene_color = fx_%s(rotated_uv);\n" % ids
			
			f += "\t// Apply Master Brightness Global override\n"
			f += "\tscene_color.rgb *= u_master_brightness;\n"
			f += "\t\n"
			f += "\t// Calculate grayscale luminance for Saturation Global blend\n"
			f += "\tfloat luma = dot(scene_color.rgb, vec3(0.299, 0.587, 0.114));\n"
			f += "\tscene_color.rgb = mix(vec3(luma), scene_color.rgb, u_master_saturation);\n"
			f += "\t\n"
			f += "\tCOLOR = scene_color;\n"
			f += "}\n"
			
	return f



func _rename_word(text: String, from_name: String, to_name: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("\\b%s\\b" % from_name)
	return re.sub(text, to_name, true)


func _decl_line(rec: Dictionary) -> String:
	var hint: String = ""
	if rec["hint"] != "":
		hint = " : %s" % rec["hint"]
	return "uniform %s %s%s = %s;" % [rec["type"], rec["name"], hint, rec["literal"]]


# =========================================================================
# PARSER: one uniform line -> uniform record (empty Dictionary if not a uniform line)
# =========================================================================
func _parse_uniform_line(line: String, recipe_id: String) -> Dictionary:
	var m: RegExMatch = _re_uniform.search(line)
	if m == null:
		return {}
	var type: String = m.get_string(1)
	var base: String = m.get_string(2)
	var literal: String = m.get_string(4).strip_edges()
	var tags: Dictionary = _parse_tags(m.get_string(5))

	var mn: float = float(tags["min"]) if tags.has("min") else -INF
	var mx: float = float(tags["max"]) if tags.has("max") else INF
	var sens: float = 0.01
	if tags.has("sens"):
		sens = float(tags["sens"])
	elif not is_inf(mn) and not is_inf(mx):
		sens = (mx - mn) / 100.0

	var channels: PackedStringArray = PackedStringArray(["VALUE"])
	if type == "vec2":
		channels = PackedStringArray(["X", "Y"])
	elif type == "vec4":
		channels = PackedStringArray(["R", "G", "B", "A"])
	if tags.has("channels"):
		channels = PackedStringArray()
		for c in String(tags["channels"]).split(","):
			channels.append(c.strip_edges())

	return {
		"recipe": recipe_id,        # "" = owned by the pass itself
		"base_name": base,          # name as written in the recipe
		"name": base,               # final name in the assembled shader (prefixed unless global)
		"type": type,
		"hint": m.get_string(3).strip_edges(),
		"literal": literal,
		"default": _parse_literal(type, literal),
		"label": str(tags.get("label", base.trim_prefix("u_").replace("_", " ").capitalize())),
		"min": mn,
		"max": mx,
		"sens": sens,               # recommended sensitivity
		"channels": channels,
		"is_global": tags.has("global"),
	}


func _parse_tags(comment: String) -> Dictionary:
	var tags: Dictionary = {}
	for part in comment.split("|"):
		var p: String = part.strip_edges()
		if not p.begins_with("@"):
			continue
		p = p.substr(1)
		var sp: int = p.find(" ")
		if sp == -1:
			tags[p] = true
		else:
			tags[p.substr(0, sp)] = p.substr(sp + 1).strip_edges()
	return tags


func _parse_literal(type: String, text: String) -> Variant:
	var t: String = text.strip_edges()
	if type == "float":
		return float(t)
	var nums: Array = []
	var open: int = t.find("(")
	var close: int = t.rfind(")")
	if open != -1 and close > open:
		for s in t.substr(open + 1, close - open - 1).split(","):
			nums.append(float(s.strip_edges()))
	if type == "vec2":
		if nums.size() == 1:
			nums.append(nums[0])
		while nums.size() < 2:
			nums.append(0.0)
		return Vector2(nums[0], nums[1])
	if nums.size() == 1:
		return Color(nums[0], nums[0], nums[0], nums[0])
	while nums.size() < 4:
		nums.append(0.0 if nums.size() < 3 else 1.0)
	return Color(nums[0], nums[1], nums[2], nums[3])


# =========================================================================
# VALUE HELPERS (the menus and the tweak console read these)
# =========================================================================
## Number of Tier 4 parameters (channels) for a uniform. 1 means Tier 3 can jump straight to Tier 5.
func channel_count(rec: Dictionary) -> int:
	return rec["channels"].size()

func get_component(value: Variant, type: String, idx: int) -> float:
	match type:
		"vec2":
			var v2: Vector2 = value
			return v2[idx]
		"vec4":
			var c4: Color = value
			return c4[idx]
	return float(value)

func set_component(value: Variant, type: String, idx: int, v: float) -> Variant:
	match type:
		"vec2":
			var v2: Vector2 = value
			v2[idx] = v
			return v2
		"vec4":
			var c4: Color = value
			c4[idx] = v
			return c4
	return v

func clamp_component(rec: Dictionary, v: float) -> float:
	return clampf(v, rec["min"], rec["max"])

## Default value of one channel (Tier 5 "default" row).
func default_component(rec: Dictionary, idx: int) -> float:
	return get_component(rec["default"], rec["type"], idx)

## Sensitivity steps built around the recommended value; the recommended one sits at index 2.
func sens_ladder(rec: Dictionary) -> Array:
	var s: float = rec["sens"]
	return [s * 0.1, s * 0.5, s, s * 5.0, s * 10.0]

## Seed missing values with defaults and push everything into the material.
## Pass in the per-pass value cache (keyed by final uniform name).
func apply_values(mat: ShaderMaterial, records: Array, values: Dictionary) -> void:
	for rec in records:
		var n: String = rec["name"]
		if not values.has(n):
			values[n] = rec["default"]
		mat.set_shader_parameter(n, values[n])

## Put values back to defaults. recipe_id == "" resets everything (pass-level RESET);
## a recipe id resets only that formula (Tier 3 row 0). Call apply_values afterwards.
func reset_values(records: Array, values: Dictionary, recipe_id: String = "") -> void:
	for rec in records:
		if recipe_id != "" and rec["recipe"] != recipe_id:
			continue
		values[rec["name"]] = rec["default"]

## Tier 3 list for a formula.
func uniforms_for_recipe(records: Array, recipe_id: String) -> Array:
	var out: Array = []
	for rec in records:
		if rec["recipe"] == recipe_id and not rec["is_global"]:
			out.append(rec)
	return out

## Tier 3 list for the GLOBALS row.
func global_uniforms(records: Array) -> Array:
	var out: Array = []
	for rec in records:
		if rec["is_global"]:
			out.append(rec)
	return out


# =========================================================================
# STARTER RECIPES
# =========================================================================
func _register_builtin_recipes() -> void:
	# 1. FBM (Smooth Noise)
	_register("fbm_static", PASS_PATTERN, "DOMAIN-WARP: LAYERED MIX", SRC_FBM, false)
	_register("fbm_cosine", PASS_PATTERN, "DOMAIN-WARP: COSINE PALETTE", SRC_FBM_COSINE, false)
	_register("fbm_chrono", PASS_PATTERN, "DOMAIN-WARP: CHRONO MORPH", SRC_FBM_CHRONO, false)
	_register("fbm_cyber", PASS_PATTERN, "DOMAIN-WARP: CYBER VEINS", SRC_FBM_CYBER, false)
	
	# 2. GYROID (Trig Labyrinths)
	_register("gyroid_static", PASS_PATTERN, "GYROID: LABYRINTH CORE", SRC_GYROID_STATIC, false)
	_register("gyroid_cosine", PASS_PATTERN, "GYROID: COSINE PALETTE", SRC_GYROID_COSINE, false)
	_register("gyroid_chrono", PASS_PATTERN, "GYROID: CHRONO MORPH", SRC_GYROID_CHRONO, false)
	_register("gyroid_cyber", PASS_PATTERN, "GYROID: CYBER VEINS", SRC_GYROID_CYBER, false)
	
	# 3. VORONOI (Crystalline Cells)
	_register("voronoi_static", PASS_PATTERN, "VORONOI: CRYSTAL CORE", SRC_VORONOI_STATIC, false)
	_register("voronoi_cosine", PASS_PATTERN, "VORONOI: COSINE PALETTE", SRC_VORONOI_COSINE, false)
	_register("voronoi_chrono", PASS_PATTERN, "VORONOI: CHRONO MORPH", SRC_VORONOI_CHRONO, false)
	_register("voronoi_cyber", PASS_PATTERN, "VORONOI: CYBER VEINS", SRC_VORONOI_CYBER, false)
	
	# 4. PLASMA (Sinusoidal Fluids)
	_register("plasma_static", PASS_PATTERN, "PLASMA: FLUID GRADIENT", SRC_PLASMA_STATIC, false) 
	_register("plasma_cosine", PASS_PATTERN, "PLASMA: COSINE PALETTE", SRC_PLASMA_COSINE, false) 
	_register("plasma_chrono", PASS_PATTERN, "PLASMA: CHRONO MORPH", SRC_PLASMA_CHRONO, false)   
	_register("plasma_cyber", PASS_PATTERN, "PLASMA: CYBER VEINS", SRC_PLASMA_CYBER, false)     
	
	# 5. Basic Shapes 
	# Geometry Engines
	_register("shapes_static", PASS_PATTERN, "GEOMETRY: SOLID SHAPES", SRC_BASIC_SHAPES, false)
	_register("shapes_cosine", PASS_PATTERN, "GEOMETRY: SOLID COSINE", SRC_SHAPES_COSINE, false) 
	_register("shapes_chrono", PASS_PATTERN, "GEOMETRY: SOLID CHRONO", SRC_SHAPES_CHRONO, false) 
	
	# Hollow Wireframe Geometry
	_register("shapes_lines", PASS_PATTERN, "GEOMETRY: HOLLOW WIREFRAMES", SRC_BASIC_LINES, false)
	_register("lines_cosine", PASS_PATTERN, "GEOMETRY: WIREFRAME COSINE", SRC_LINES_COSINE, false) 
	_register("lines_chrono", PASS_PATTERN, "GEOMETRY: WIREFRAME CHRONO", SRC_LINES_CHRONO, false)  
 

	# Pass 2 (Warp Modules) - Stackable!
	_register("kaleidoscope", PASS_WARP, "KALEIDOSCOPE REFLECTION", SRC_KALEIDOSCOPE, true)
	_register("swirl", PASS_WARP, "RADIAL SWIRL", SRC_SWIRL, true)
	_register("polar_map", PASS_WARP, "POLAR TUNNEL MAP", SRC_POLAR_MAP, true) 
	_register("chromatic_ripple", PASS_WARP, "CHROMATIC RIPPLE LENS", SRC_CHROMATIC_RIPPLE, true)
	_register("droste_spiral", PASS_WARP, "DROSTE INFINITE SPIRAL", SRC_DROSTE_SPIRAL, true) 
	_register("polar_kaleidoscope", PASS_WARP, "POLAR KALEIDOSCOPE", SRC_POLAR_KALEIDOSCOPE, true)
	_register("field_shift", PASS_WARP, "VECTOR FIELD MELT", SRC_FIELD_SHIFT, true)
	_register("fisheye_bulb", PASS_WARP, "FISHEYE BULB LENS", SRC_FISHEYE_BULB, true)
	
	
	# Pass 3 - filters
	_register("edge_glow", PASS_FILTER, "ANALOG EDGE GLOW", SRC_EDGE_GLOW, false)
	_register("crt_screen", PASS_FILTER, "📺 CRT MONITOR SIMULATOR", SRC_CRT_SCREEN, false)
	_register("vhs_glitch", PASS_FILTER, "📼 VHS TAPE GLITCH", SRC_VHS_GLITCH, false)
	_register("pixel_crusher", PASS_FILTER, "🕹️ PIXELATION RESOLUTION CRUSHER", SRC_PIXEL_CRUSHER, false)
	_register("vignette_blur", PASS_FILTER, "🎬 CINEMATIC VIGNETTE BLUR", SRC_VIGNETTE_BLUR, false)
	_register("god_rays", PASS_FILTER, "☀️ VOLUMETRIC LIGHT STREAKS", SRC_GOD_RAYS, false)
	_register("halftone_dots", PASS_FILTER, "🎨 HALFTONE DOT MATRIX", SRC_HALFTONE_DOTS, false)
	_register("ascii_art", PASS_FILTER, "📟 ASCII CHARACTER TERMINAL", SRC_ASCII_ART, false)
	_register("oil_painting", PASS_FILTER, "🖌️ OIL PAINTING CANVAS", SRC_OIL_PAINTING, false)
	_register("p3_fisheye_bulb", PASS_FILTER, "FISHEYE BULB LENS", SRC_FISHEYE_BULB, true)



const SRC_P3_FISHEYE_BULB: String = """
uniform vec2 u_lens_center = vec2(0.5, 0.5); // @label Bulb Center | @min 0.0 | @max 1.0 | @sens 0.01
uniform float u_lens_radius = 0.5; // @label Bulb Radius | @min 0.1 | @max 1.5 | @sens 0.02
uniform float u_lens_power = 1.5; // @label Pinch Intensity | @min 0.1 | @max 4.0 | @sens 0.05

vec2 fx_fisheye_bulb(vec2 uv) {
	// Calculate the distance vector from the pixel to the center of our bulb lens
	vec2 p = uv - u_lens_center;
	float d = length(p);
	
	// Check if the current pixel coordinate falls within our lens bubble radius
	if (d < u_lens_radius) {
		// Normalize the coordinate space relative to the radius of the bulb
		float norm_d = d / u_lens_radius;
		
		// Run a non-linear exponential warp factor on the normalized radius
		float warp = pow(norm_d, u_lens_power);
		
		// Rescale the vector from the center based on the magnification power curve
		return u_lens_center + normalize(p) * warp * u_lens_radius;
	}
	
	// If outside the lens boundary, leave the coordinate tracking flat and untouched
	return uv;
}
"""


const SRC_OIL_PAINTING: String = """
uniform float u_brush_radius = 4.0; // @label Brush Stroke Size | @min 1.0 | @max 8.0 | @sens 0.5
uniform float u_paint_coarseness = 3.0; // @label Color Clustering | @min 1.0 | @max 10.0 | @sens 0.5
uniform float u_canvas_texture = 0.08; // @label Canvas Paper Grain | @min 0.0 | @max 0.3 | @sens 0.01

// Simple generator to layer on canvas fabric weave grain lines
float paint_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 fx_oil_painting(vec2 uv) {
	// Query the layout dimensions of the texture from previous passes
	vec2 tex_size = vec2(textureSize(u_warped_texture, 0));
	vec2 src_step = 1.0 / tex_size;
	
	// Create accumulation buffers for painterly color averages
	vec3 color_sum = vec3(0.0);
	float weight_sum = 0.0;
	
	int radius = int(floor(u_brush_radius));
	
	// Scan adjacent pixel clusters within our artistic brush boundary box
	for (int j = -radius; j <= radius; j++) {
		for (int i = -radius; i <= radius; i++) {
			vec2 offset = vec2(float(i), float(j)) * src_step;
			vec3 tex_sample = texture(u_warped_texture, clamp(uv + offset, 0.0, 1.0)).rgb;
			
			// Cluster colors into coarse brackets to group strokes together
			vec3 clustered = floor(tex_sample * u_paint_coarseness) / u_paint_coarseness;
			
			color_sum += tex_sample;
			weight_sum += 1.0;
		}
	}
	
	// Calculate the flattened canvas pigment core color
	vec3 paint_pigment = color_sum / max(weight_sum, 1.0);
	
	// Layer an organic interlaced canvas thread texture over the paint layers
	float fabric_weave = paint_hash(floor(uv * tex_size)) * u_canvas_texture;
	paint_pigment += vec3(fabric_weave - (u_canvas_texture * 0.5));
	
	return vec4(paint_pigment, 1.0);
}
"""


const SRC_ASCII_ART: String = """
uniform float u_terminal_columns = 80.0; // @label Text Columns | @min 20 | @max 180 | @sens 2
uniform float u_font_stretch = 1.5; // @label Character Height Ratio | @min 0.5 | @max 3.0 | @sens 0.05
uniform vec4 u_text_color : source_color = vec4(0.0, 1.0, 0.3, 1.0); // @label Font Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_terminal_bg : source_color = vec4(0.01, 0.02, 0.01, 1.0); // @label Terminal Background | @min 0 | @max 1 | @sens 0.02

// A procedural layout that mocks character glyph shapes based on cell coordinates
float ascii_character_glyph(int character_id, vec2 cell_uv) {
	vec2 p = abs(cell_uv - 0.5);
	
	if (character_id == 4) { // Dense character block '#'
		return step(0.1, max(p.x, p.y)) * step(max(p.x, p.y), 0.45);
	}
	if (character_id == 3) { // Bold character 'X'
		return step(abs(p.x - p.y), 0.08) * step(max(p.x, p.y), 0.4);
	}
	if (character_id == 2) { // Cross character '+'
		return (step(p.x, 0.06) * step(p.y, 0.35)) + (step(p.y, 0.06) * step(p.x, 0.35));
	}
	if (character_id == 1) { // Center dash character '-'
		return step(abs(cell_uv.y - 0.5), 0.05) * step(p.x, 0.3);
	}
	// Tiny dot character '.'
	return step(length(cell_uv - 0.5), 0.08);
}

vec4 fx_ascii_art(vec2 uv) {
	// 1. Establish character terminal row grid scaling configurations
	vec2 text_scale = vec2(u_terminal_columns, u_terminal_columns * u_font_stretch);
	
	// Segment the coordinate layout down into individual grid cells
	vec2 blocky_uv = floor(uv * text_scale) / text_scale;
	vec2 local_cell_uv = fract(uv * text_scale);
	
	// 2. Measure local luminance inside the character block coordinate boundaries
	vec4 source_sample = texture(u_warped_texture, blocky_uv);
	float brightness = dot(source_sample.rgb, vec3(0.299, 0.587, 0.114));
	
	// Convert brightness score thresholds into a discrete character selector ID
	int character_selector = int(floor(brightness * 5.0));
	character_selector = clamp(character_selector, 0, 4);
	
	// 3. Render the shape of the chosen character glyph inside the local cell block
	float glyph_mask = ascii_character_glyph(character_selector, local_cell_uv);
	
	// If the background cell brightness is completely dark, suppress drawing the glyph text
	if (brightness < 0.05) { glyph_mask = 0.0; }
	
	// Mix character matrix inks over the command line terminal base screen backdrop
	vec3 output_color = mix(u_terminal_bg.rgb, u_text_color.rgb, glyph_mask);
	
	return vec4(output_color, 1.0);
}
"""


const SRC_HALFTONE_DOTS: String = """
uniform float u_dot_frequency = 45.0; // @label Dot Frequency Grid | @min 10.0 | @max 150.0 | @sens 1.0
uniform float u_halftone_sharpness = 0.08; // @label Dot Crispness | @min 0.01 | @max 0.4 | @sens 0.005
uniform vec4 u_ink_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // @label Screenprint Ink | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_paper_color : source_color = vec4(0.95, 0.95, 0.9, 1.0); // @label Newsprint Paper | @min 0 | @max 1 | @sens 0.02

vec4 fx_halftone_dots(vec2 uv) {
	// Sample the compiled background canvas texture from previous passes
	vec4 pixel_color = texture(u_warped_texture, uv);
	
	// Convert the RGB pixel stream into a clean scalar luminance (brightness) score
	float luminance = dot(pixel_color.rgb, vec3(0.299, 0.587, 0.114));
	
	// Slice coordinate space up into a repeating dot matrix grid cell network
	vec2 grid = fract(uv * u_dot_frequency) - 0.5;
	float dot_radius = length(grid);
	
	// The dot size scales proportionally based on local luminance intensity
	float target_size = luminance * 0.707; // 0.707 prevents dots from totally disappearing
	
	// Evaluate the edge mask boundaries of each print ink circle cell
	float print_mask = smoothstep(target_size, target_size - u_halftone_sharpness, dot_radius);
	
	// Blend between your vintage textured paper stock color and your dark printing press ink
	return mix(u_paper_color, u_ink_color, print_mask);
}
"""


const SRC_GOD_RAYS: String = """
uniform float u_ray_density = 0.95; // @label Ray Length | @min 0.5 | @max 0.99 | @sens 0.01
uniform float u_ray_weight = 0.5; // @label Beam Exposure | @min 0.0 | @max 1.5 | @sens 0.05
uniform float u_ray_decay = 0.98; // @label Falloff Decay | @min 0.9 | @max 1.0 | @sens 0.005
uniform vec2 u_ray_source = vec2(0.5, 0.5); // @label Light Origin | @min 0.0 | @max 1.0 | @sens 0.01

vec4 fx_god_rays(vec2 uv) {
	// Calculate a directional vector pointing from the pixel back to the light center source
	vec2 delta_uv = (uv - u_ray_source);
	
	// Scale the step division vector based on density parameters
	delta_uv *= 1.0 / 8.0 * u_ray_density; // 8-tap approximation loop
	
	// Capture the baseline core image pixel color
	vec4 base_color = texture(u_warped_texture, uv);
	
	// Create accumulation buffers for the projected light streaks
	vec3 light_stream = base_color.rgb;
	float current_illumination = 1.0;
	
	vec2 trace_uv = uv;
	
	// Step along the directional vector, sampling texture brightness layers
	for (int i = 0; i < 8; i++) {
		trace_uv -= delta_uv;
		vec3 sample_layer = texture(u_warped_texture, clamp(trace_uv, 0.0, 1.0)).rgb;
		
		// Apply exponential decay attenuation curves
		sample_layer *= current_illumination * u_ray_weight;
		light_stream += sample_layer;
		current_illumination *= u_ray_decay;
	}
	
	// Blend the accumulated light beams back over the top of the crisp baseline color
	return vec4(base_color.rgb + light_stream * 0.15, 1.0);
}
"""


const SRC_VIGNETTE_BLUR: String = """
uniform float u_vignette_extent = 0.5; // @label Vignette Radius | @min 0.1 | @max 1.5 | @sens 0.02
uniform float u_vignette_softness = 0.45; // @label Vignette Softness | @min 0.05 | @max 1.0 | @sens 0.02
uniform float u_blur_radius = 0.015; // @label Edge Blur Strength | @min 0.0 | @max 0.05 | @sens 0.001

vec4 fx_vignette_blur(vec2 uv) {
	// Center space to calculate radial distance for the lens edge
	vec2 center_dist = uv - 0.5;
	float d = length(center_dist);
	
	// 1. Calculate the vignette falloff mask using smoothstep
	float vignette = smoothstep(u_vignette_extent, u_vignette_extent - u_vignette_softness, d);
	
	// 2. RADIAL BLUR PASS: The further from the center, the more samples we gather
	float current_blur = smoothstep(u_vignette_extent * 0.5, u_vignette_extent, d) * u_blur_radius;
	
	vec4 color_accumulation = vec4(0.0);
	float total_weight = 0.0;
	
	// 4-tap box blur array offsets for smooth edge sampling
	vec2 blur_offsets[4] = vec2[](
		vec2(-1.0, -1.0), vec2(1.0, -1.0),
		vec2(-1.0, 1.0), vec2(1.0, 1.0)
	);
	
	// Gather adjacent pixel weights based on radial blur gradient
	for (int i = 0; i < 4; i++) {
		vec2 sample_uv = uv + blur_offsets[i] * current_blur;
		color_accumulation += texture(u_warped_texture, clamp(sample_uv, 0.0, 1.0));
		total_weight += 1.0;
	}
	
	vec4 final_sample = color_accumulation / total_weight;
	
	// Apply the dark vignette frame overlay onto the blurred pixel stream
	final_sample.rgb *= vignette;
	
	return vec4(final_sample.rgb, 1.0);
}
"""


const SRC_PIXEL_CRUSHER: String = """
uniform float u_pixel_grid_size = 128.0; // @label Pixel Grid Blocks | @min 16 | @max 512 | @sens 4
uniform float u_color_depth_steps = 8.0; // @label Color Palette Bits | @min 2 | @max 32 | @sens 1
uniform float u_dither_strength = 0.15; // @label Retro Dither Noise | @min 0.0 | @max 0.5 | @sens 0.01

// Simple grid noise generator to create dithered checkerboard pixels
float pixel_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec4 fx_pixel_crusher(vec2 uv) {
	// 1. RESOLUTION CRUSH: Snap the smooth UV space to a low-res pixel grid blocks count
	vec2 blocky_uv = floor(uv * u_pixel_grid_size) / u_pixel_grid_size;
	
	// Sample the scene texture at our blocky coordinate steps
	vec4 pixel_color = texture(u_warped_texture, blocky_uv);
	
	// 2. RETRO DITHER: Calculate an old-school 50% checkerboard dither pattern to fake smooth shading
	float dither = pixel_hash(floor(uv * u_pixel_grid_size)) * u_dither_strength;
	pixel_color.rgb += vec3(dither - (u_dither_strength * 0.5));
	
	// 3. COLOR PALETTE CRUSH: Force the smooth color floats into blocky bit-depth chunks
	pixel_color.r = floor(pixel_color.r * u_color_depth_steps) / u_color_depth_steps;
	pixel_color.g = floor(pixel_color.g * u_color_depth_steps) / u_color_depth_steps;
	pixel_color.b = floor(pixel_color.b * u_color_depth_steps) / u_color_depth_steps;
	
	return vec4(pixel_color.rgb, 1.0);
}
"""

const SRC_VHS_GLITCH: String = """
uniform float u_vhs_noise_mix = 0.15; // @label Tape Static Noise | @min 0.0 | @max 0.5 | @sens 0.01
uniform float u_shake_frequency = 4.0; // @label Tracking Jitter | @min 0.0 | @max 15.0 | @sens 0.5
uniform float u_chromatic_split = 0.008; // @label Color Bleeding | @min 0.0 | @max 0.04 | @sens 0.001
uniform float u_glitch_frequency = 1.5; // @label Signal Tearing | @min 0.0 | @max 5.0 | @sens 0.1

// Simple hash to generate pseudo-random values for tracking noise lines
float vhs_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 fx_vhs_glitch(vec2 uv) {
	float t = u_time;
	vec2 warped_uv = uv;
	
	// 1. Calculate horizontal pixel tearing strips using sine wave steps and noise
	float tear_wave = sin(uv.y * 10.0 + t * u_shake_frequency) * cos(uv.y * 25.0 - t);
	float tear_trigger = step(0.92, vhs_hash(vec2(floor(uv.y * 15.0), floor(t * 8.0))));
	warped_uv.x += tear_wave * u_glitch_frequency * 0.02 * tear_trigger;
	
	// 2. Vertical tracking jitter (shakes the frame rapidly up and down based on a timer)
	float vertical_shake = vhs_hash(vec2(floor(t * u_shake_frequency), 1.0)) * 0.004;
	warped_uv.y += vertical_shake * step(0.85, vhs_hash(vec2(t, 0.0)));
	
	// 3. Chromatic Channel Bleeding (Simulates analog color misalignments)
	// We separate the Red and Blue channels into separate lookup coordinates
	float r_channel = texture(u_warped_texture, warped_uv + vec2(u_chromatic_split, 0.0)).r;
	float g_channel = texture(u_warped_texture, warped_uv).g;
	float b_channel = texture(u_warped_texture, warped_uv - vec2(u_chromatic_split, 0.0)).b;
	vec3 analog_color = vec3(r_channel, g_channel, b_channel);
	
	// 4. Inject magnetic tape grain and snow static lines
	float static_grain = vhs_hash(uv + vec2(t * 0.1));
	float line_noise = step(0.98, vhs_hash(vec2(0.0, uv.y + t * 5.0))) * 0.3;
	
	// Blend the noise elements into the final canvas
	vec3 final_color = mix(analog_color, vec3(static_grain), u_vhs_noise_mix);
	final_color += vec3(line_noise) * u_vhs_noise_mix * 2.0;
	
	return vec4(final_color, 1.0);
}
"""


const SRC_CRT_SCREEN: String = """
uniform float u_scanline_density = 400.0; // @label Scanline Density | @min 50 | @max 1000 | @sens 10
uniform float u_scanline_opacity = 0.25; // @label Scanline Opacity | @min 0.0 | @max 1.0 | @sens 0.02
uniform float u_pixel_grille = 0.2; // @label RGB Mask Strength | @min 0.0 | @max 1.0 | @sens 0.02
uniform float u_barrel_distortion = 0.08; // @label Screen Curvature | @min 0.0 | @max 0.4 | @sens 0.01
uniform float u_vignette_hold = 0.6; // @label Screen Border Shadow | @min 0.1 | @max 1.0 | @sens 0.02

// Helper function to simulate a curved CRT tube surface
vec2 crt_curved_uv(vec2 uv) {
	vec2 p = uv - 0.5;
	float d = dot(p, p);
	// Deform coordinates outward proportional to their squared distance from the center
	p *= 1.0 + d * u_barrel_distortion;
	return p + 0.5;
}

vec4 fx_crt_screen(vec2 uv) {
	// 1. Apply Screen Curvature Distortion
	vec2 warped_uv = crt_curved_uv(uv);
	
	// If the curved coordinates stretch past the physical screen bezel, clip to black
	if (warped_uv.x < 0.0 || warped_uv.x > 1.0 || warped_uv.y < 0.0 || warped_uv.y > 1.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	
	// Sample the compiled scene texture from the previous passes
	vec4 base_color = texture(u_warped_texture, warped_uv);
	
	// 2. Inject Horizontal Scanlines
	float scanline = sin(warped_uv.y * u_scanline_density * 6.28318) * 0.5 + 0.5;
	// Lerp based on user opacity preference
	base_color.rgb = mix(base_color.rgb, base_color.rgb * scanline, u_scanline_opacity);
	
	// 3. Inject Vertical RGB Shadow Mask / Aperture Grille
	float grille = sin(warped_uv.x * u_scanline_density * 1.5 * 6.28318) * 0.5 + 0.5;
	base_color.rgb = mix(base_color.rgb, base_color.rgb * grille, u_pixel_grille);
	
	// 4. Subtle Screen Border Vignette Falloff
	vec2 vig_uv = warped_uv * (1.0 - warped_uv.yx);
	float vig = vig_uv.x * vig_uv.y * 15.0;
	base_color.rgb *= pow(vig, u_vignette_hold);
	
	return base_color;
}
"""


const SRC_FISHEYE_BULB: String = """
uniform vec2 u_lens_center = vec2(0.5, 0.5); // @label Bulb Center | @min 0.0 | @max 1.0 | @sens 0.01
uniform float u_lens_radius = 0.5; // @label Bulb Radius | @min 0.1 | @max 1.5 | @sens 0.02
uniform float u_lens_power = 1.5; // @label Pinch Intensity | @min 0.1 | @max 4.0 | @sens 0.05

vec2 fx_fisheye_bulb(vec2 uv) {
	// Calculate the distance vector from the pixel to the center of our bulb lens
	vec2 p = uv - u_lens_center;
	float d = length(p);
	
	// Check if the current pixel coordinate falls within our lens bubble radius
	if (d < u_lens_radius) {
		// Normalize the coordinate space relative to the radius of the bulb
		float norm_d = d / u_lens_radius;
		
		// Run a non-linear exponential warp factor on the normalized radius
		float warp = pow(norm_d, u_lens_power);
		
		// Rescale the vector from the center based on the magnification power curve
		return u_lens_center + normalize(p) * warp * u_lens_radius;
	}
	
	// If outside the lens boundary, leave the coordinate tracking flat and untouched
	return uv;
}
"""


const SRC_FIELD_SHIFT: String = """
uniform vec2 u_field_frequency = vec2(4.0, 4.0); // @label Wave Density | @min 0.5 | @max 16.0 | @sens 0.1
uniform float u_field_strength = 0.05; // @label Glass Thickness | @min 0.0 | @max 0.25 | @sens 0.005
uniform float u_shift_speed = 0.8; // @label Melt Speed | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_wave_interlace = 2.0; // @label Wave Cross-Folding | @min 0.5 | @max 5.0 | @sens 0.05

vec2 fx_field_shift(vec2 uv) {
	float t = u_time * u_shift_speed;
	
	// Create cross-folding trigonometric vector forces
	float force_x = sin(uv.x * u_field_frequency.x + t) * cos(uv.y * u_field_frequency.y * u_wave_interlace - t);
	float force_y = cos(uv.y * u_field_frequency.y + t) * sin(uv.x * u_field_frequency.x * u_wave_interlace + t);
	
	// Recombine forces into a smooth displacement vector map
	vec2 displacement = vec2(force_x, force_y) * u_field_strength;
	
	// Displace the lookup UV space smoothly
	return uv + displacement;
}
"""


const SRC_POLAR_KALEIDOSCOPE: String = """
uniform float u_sectors = 8.0; // @label Radial Slices | @min 2.0 | @max 32.0 | @sens 1.0
uniform float u_rings = 3.0; // @label Concentric Rings | @min 1.0 | @max 12.0 | @sens 1.0
uniform float u_ring_zoom = 1.5; // @label Ring Scaling | @min 0.5 | @max 5.0 | @sens 0.05
uniform float u_rotation_speed = 0.2; // @label Slice Spin Speed | @min -2.0 | @max 2.0 | @sens 0.05
uniform float u_pulse_speed = 0.1; // @label Ring Pulse Speed | @min -1.0 | @max 1.0 | @sens 0.02

vec2 fx_polar_kaleidoscope(vec2 uv) {
	// Center the coordinates around (0.0, 0.0)
	vec2 p = uv - 0.5;
	
	// Convert space into raw polar coordinates
	float r = length(p);
	float a = atan(p.y, p.x);
	
	// 1. REFLECTION PASS A: Mirror the Angular Space (Slices)
	float angle_step = 6.2831853 / max(u_sectors, 1.0);
	a += u_time * u_rotation_speed;
	// Modulo space partitioning
	float sector_id = floor(a / angle_step);
	a = mod(a, angle_step);
	// Abs creates the mirrored reflection fold down the center of each slice
	a = abs(a - angle_step * 0.5);
	
	// 2. REFLECTION PASS B: Mirror the Radial Space (Rings)
	float radius_step = 0.5 / max(u_rings, 1.0);
	float shifting_r = r * u_ring_zoom + sin(u_time * u_pulse_speed) * 0.05;
	// Divide radius into tile grids, mirroring back and forth across cell boundaries
	float ring_id = floor(shifting_r / radius_step);
	float local_r = mod(shifting_r, radius_step);
	if (mod(ring_id, 2.0) == 1.0) {
		local_r = radius_step - local_r;
	}
	
	// Convert our twice-mirrored polar grid coordinates back to Cartesian UV space
	vec2 warped_uv = vec2(cos(a), sin(a)) * local_r + 0.5;
	
	return warped_uv;
}
"""


const SRC_DROSTE_SPIRAL: String = """
uniform float u_branches = 1.0; // @label Spiral Branches | @min 1.0 | @max 5.0 | @sens 1.0
uniform float u_twist_factor = 1.0; // @label Twist Tightness | @min -4.0 | @max 4.0 | @sens 0.05
uniform float u_spiral_zoom = 0.8; // @label Vortex Zoom | @min 0.2 | @max 3.0 | @sens 0.05
uniform float u_implode_speed = 0.2; // @label Inward Collapse Speed | @min -2.0 | @max 2.0 | @sens 0.05

vec2 fx_droste_spiral(vec2 uv) {
	// Center the coordinates around the vortex center
	vec2 p = uv - 0.5;
	
	// Avoid mathematical undefined errors at the absolute center node
	float r = max(length(p), 0.0001);
	float a = atan(p.y, p.x);
	
	// Conformal Logarithmic Mapping Engine
	// Taking the log of the radius stretches space into a linear timeline grid
	float log_r = log(r);
	
	// Apply structural twists by combining our stretched logarithmic scale and radial angle
	float spiral_x = (log_r * u_spiral_zoom) + (a * u_twist_factor * 0.1591549) - (u_time * u_implode_speed);
	float spiral_y = (a * u_branches * 0.1591549) + (log_r * u_twist_factor * 0.1591549);
	
	// Map the coordinates back into standard texture repeating tile bounds
	vec2 warped_uv = vec2(spiral_x, spiral_y);
	
	// Centering offset realignment mapping for subsequent pattern filters
	return fract(warped_uv + 0.5);
}
"""


const SRC_CHROMATIC_RIPPLE: String = """
uniform float u_ripple_frequency = 8.0; // @label Wave Frequency | @min 1.0 | @max 30.0 | @sens 0.5
uniform float u_ripple_strength = 0.03; // @label Distortion Power | @min 0.0 | @max 0.2 | @sens 0.002
uniform float u_ripple_speed = 2.0; // @label Wave Velocity | @min 0.0 | @max 5.0 | @sens 0.05
uniform vec2 u_ripple_axis = vec2(1.0, 0.0); // @label Wave Direction Vector | @min -1 | @max 1 | @sens 0.1

vec2 fx_chromatic_ripple(vec2 uv) {
	// Calculate a moving wave phase based on coordinate positioning and time
	float alignment = dot(uv, normalize(u_ripple_axis));
	float wave = sin(alignment * u_ripple_frequency - u_time * u_ripple_speed);
	
	// Create an organic warping displacement offset vector
	vec2 offset = vec2(wave) * u_ripple_strength;
	
	// Shift coordinate lookups dynamically to create shimmering liquid glass ripples
	return uv + offset;
}
"""


const SRC_POLAR_MAP: String = """
uniform float u_zoom = 1.0; // @label Tunnel Zoom | @min 0.2 | @max 5.0 | @sens 0.05
uniform float u_repeats_radial = 2.0; // @label Ring Repeats | @min 0.5 | @max 8.0 | @sens 0.5
uniform float u_spin_speed = 0.2; // @label Spin Speed | @min -2.0 | @max 2.0 | @sens 0.05
uniform float u_tunnel_speed = 0.3; // @label Tunnel Fly Speed | @min -3.0 | @max 3.0 | @sens 0.05

vec2 fx_polar_map(vec2 uv) {
	// Center coordinates around (0.0, 0.0)
	vec2 p = uv - 0.5;
	
	// Calculate the polar metrics: r (radius/distance) and a (angle/rotation)
	float r = length(p);
	float a = atan(p.y, p.x);
	
	// 1. Transform Radius into a continuous tunnel depth layout
	// Inverting r makes the center fly forward or backward over time
	float tunnel_depth = (1.0 / max(r, 0.001)) * u_zoom;
	float radial_uv = tunnel_depth + (u_time * u_tunnel_speed);
	
	// 2. Transform Angle into a clean, normalized looping wrap (0.0 to 1.0)
	// Adding time spins the polar coordinate mapping wheel smoothly
	float angular_uv = (a + 3.14159265) / 6.2831853;
	angular_uv = angular_uv * u_repeats_radial + (u_time * u_spin_speed);
	
	// Reassemble back into standard coordinate space for the next pass/texture read
	return vec2(angular_uv, radial_uv);
}
"""


const SRC_LINES_COSINE: String = """
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001
uniform float u_line_thickness = 0.02; // @label Line Thickness | @min 0.005 | @max 0.2 | @sens 0.002
uniform float u_palette_frequency = 4.0; // @label Color Ring Density | @min 0.5 | @max 15.0 | @sens 0.1
uniform float u_color_cycle_speed = 0.5; // @label Color Cycle Speed | @min 0 | @max 3 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.0, 0.33, 0.67, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

vec2 lcos_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float sdf_circle_lc(vec2 p, float r) { return length(p) - r; }
float sdf_box_lc(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdf_triangle_lc(vec2 p, float r) {
	float k = sqrt(3.0); p.x = abs(p.x) - r; p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0); return -length(p) * sign(p.y);
}
float sdf_star_lc(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229); vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x); p -= 2.0 * max(dot(k1, p), 0.0) * k1; p -= 2.0 * max(dot(k2, p), 0.0) * k2; p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r); vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}
float sdf_hexagon_lc(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269); p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy; p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_lines_cosine(vec2 uv) {
	vec2 p = uv - 0.5 - u_position;
	p = lcos_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	if (choice == 0) { distance_score = sdf_circle_lc(p, u_scale); }
	else if (choice == 1) { distance_score = sdf_box_lc(p, vec2(u_scale)); }
	else if (choice == 2) { distance_score = sdf_triangle_lc(p, u_scale * 1.2); }
	else if (choice == 3) { distance_score = sdf_star_lc(p, u_scale, 0.45); }
	else { distance_score = sdf_hexagon_lc(p, u_scale); }
	
	float line_surface = abs(distance_score) - u_line_thickness;
	float line_mask = smoothstep(u_edge_softness, 0.0, line_surface);
	
	// Drive the color phase globally using the base distance vector
	float t = (distance_score * u_palette_frequency) + (u_time * u_color_cycle_speed);
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * t + u_color_d.rgb));
	
	return vec4(cos_color * line_mask, 1.0);
}
"""
const SRC_LINES_CHRONO: String = """
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001
uniform float u_line_thickness = 0.02; // @label Line Thickness | @min 0.005 | @max 0.2 | @sens 0.002
uniform float u_color_morph_speed = 0.6; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_bg : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Background Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_line : source_color = vec4(0.1, 0.5, 1.0, 1.0); // @label Wireframe Core | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_glow : source_color = vec4(0.0, 1.0, 0.6, 1.0); // @label Filament Highlight | @min 0 | @max 1 | @sens 0.02

vec2 lchro_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float sdf_circle_lch(vec2 p, float r) { return length(p) - r; }
float sdf_box_lch(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdf_triangle_lch(vec2 p, float r) {
	float k = sqrt(3.0); p.x = abs(p.x) - r; p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0); return -length(p) * sign(p.y);
}
float sdf_star_lch(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229); vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x); p -= 2.0 * max(dot(k1, p), 0.0) * k1; p -= 2.0 * max(dot(k2, p), 0.0) * k2; p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r); vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}
float sdf_hexagon_lch(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269); p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy; p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_lines_chrono(vec2 uv) {
	vec2 p = uv - 0.5 - u_position;
	p = lchro_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	if (choice == 0) { distance_score = sdf_circle_lch(p, u_scale); }
	else if (choice == 1) { distance_score = sdf_box_lch(p, vec2(u_scale)); }
	else if (choice == 2) { distance_score = sdf_triangle_lch(p, u_scale * 1.2); }
	else if (choice == 3) { distance_score = sdf_star_lch(p, u_scale, 0.45); }
	else { distance_score = sdf_hexagon_lch(p, u_scale); }
	
	float line_surface = abs(distance_score) - u_line_thickness;
	float line_mask = smoothstep(u_edge_softness, 0.0, line_surface);
	
	// Isolate the exact internal center core of the stroke wire path
	float core_filament = smoothstep(u_line_thickness * 0.4, 0.0, abs(distance_score)) * line_mask;
	
	// Calculate color morph timeline values
	float timeline = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 morphing_wire = mix(u_color_line, u_color_glow, timeline);
	vec4 morphing_bg = mix(u_color_bg, u_color_line * 0.15, timeline * 0.3);
	
	vec4 final_color = mix(morphing_bg, morphing_wire, line_mask);
	final_color = mix(final_color, u_color_glow, core_filament * 0.8);
	
	return final_color;
}
"""


const SRC_SHAPES_COSINE: String = """
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001
uniform float u_palette_frequency = 4.0; // @label Color Ring Density | @min 0.5 | @max 15.0 | @sens 0.1
uniform float u_color_cycle_speed = 0.5; // @label Color Cycle Speed | @min 0 | @max 3 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.0, 0.33, 0.67, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

vec2 scos_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float sdf_circle_sc(vec2 p, float r) { return length(p) - r; }
float sdf_box_sc(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdf_triangle_sc(vec2 p, float r) {
	float k = sqrt(3.0); p.x = abs(p.x) - r; p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0); return -length(p) * sign(p.y);
}
float sdf_star_sc(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229); vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x); p -= 2.0 * max(dot(k1, p), 0.0) * k1; p -= 2.0 * max(dot(k2, p), 0.0) * k2; p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r); vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}
float sdf_hexagon_sc(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269); p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy; p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_shapes_cosine(vec2 uv) {
	vec2 p = uv - 0.5 - u_position;
	p = scos_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	if (choice == 0) { distance_score = sdf_circle_sc(p, u_scale); }
	else if (choice == 1) { distance_score = sdf_box_sc(p, vec2(u_scale)); }
	else if (choice == 2) { distance_score = sdf_triangle_sc(p, u_scale * 1.2); }
	else if (choice == 3) { distance_score = sdf_star_sc(p, u_scale, 0.45); }
	else { distance_score = sdf_hexagon_sc(p, u_scale); }
	
	// Create a sharp cutout mask for the solid shape
	float shape_mask = smoothstep(u_edge_softness, 0.0, distance_score);
	
	// Pass the spatial distance field value into our cyclical cosine generator
	float t = (distance_score * u_palette_frequency) + (u_time * u_color_cycle_speed);
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * t + u_color_d.rgb));
	
	// Black out the area outside the shape boundary
	return vec4(cos_color * shape_mask, 1.0);
}
"""
const SRC_SHAPES_CHRONO: String = """
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001
uniform float u_color_morph_speed = 0.6; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_bg : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Background Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_shape : source_color = vec4(0.9, 0.2, 0.4, 1.0); // @label Shape Core | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_rim : source_color = vec4(0.0, 1.0, 0.8, 1.0); // @label Rim Highlight | @min 0 | @max 1 | @sens 0.02

vec2 schro_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float sdf_circle_sch(vec2 p, float r) { return length(p) - r; }
float sdf_box_sch(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdf_triangle_sch(vec2 p, float r) {
	float k = sqrt(3.0); p.x = abs(p.x) - r; p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0); return -length(p) * sign(p.y);
}
float sdf_star_sch(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229); vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x); p -= 2.0 * max(dot(k1, p), 0.0) * k1; p -= 2.0 * max(dot(k2, p), 0.0) * k2; p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r); vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}
float sdf_hexagon_sch(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269); p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy; p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_shapes_chrono(vec2 uv) {
	vec2 p = uv - 0.5 - u_position;
	p = schro_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	if (choice == 0) { distance_score = sdf_circle_sch(p, u_scale); }
	else if (choice == 1) { distance_score = sdf_box_sch(p, vec2(u_scale)); }
	else if (choice == 2) { distance_score = sdf_triangle_sch(p, u_scale * 1.2); }
	else if (choice == 3) { distance_score = sdf_star_sch(p, u_scale, 0.45); }
	else { distance_score = sdf_hexagon_sch(p, u_scale); }
	
	float shape_mask = smoothstep(u_edge_softness, 0.0, distance_score);
	
	// Create an inline inner glow mask tracking the shape's boundary rim
	float rim_mask = smoothstep(-0.06, 0.0, distance_score) * shape_mask;
	
	// Time-based color morph interpolation shifts
	float timeline = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 morphing_core = mix(u_color_shape, u_color_rim, timeline);
	vec4 morphing_bg = mix(u_color_bg, u_color_shape * 0.2, timeline * 0.4);
	
	// Composite background, core face, and illuminated rim together
	vec4 final_color = mix(morphing_bg, morphing_core, shape_mask);
	final_color = mix(final_color, u_color_rim, rim_mask * 0.7);
	
	return final_color;
}
"""


const SRC_BASIC_LINES: String = """
// Identical transform uniforms to keep the user experience consistent
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001

// NEW: Control the thickness of the hollow outline vector path
uniform float u_line_thickness = 0.02; // @label Line Thickness | @min 0.005 | @max 0.2 | @sens 0.002

uniform vec4 u_color_shape : source_color = vec4(0.0, 1.0, 0.8, 1.0); // @label Line Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_bg : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Background Color | @min 0 | @max 1 | @sens 0.02

// Helper: 2D Rotation Matrix
vec2 lines_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// 1. Circle SDF
float sdf_circle_l(vec2 p, float r) { return length(p) - r; }

// 2. Box SDF
float sdf_box_l(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 3. Equilateral Triangle SDF
float sdf_triangle_l(vec2 p, float r) {
	float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

// 4. Five-Pointed Star SDF
float sdf_star_l(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229);
	vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r);
	vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}

// 5. Hexagon SDF
float sdf_hexagon_l(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_shapes_lines(vec2 uv) {
	vec2 p = uv - 0.5 - u_position;
	p = lines_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	if (choice == 0) {
		distance_score = sdf_circle_l(p, u_scale);
	} else if (choice == 1) {
		distance_score = sdf_box_l(p, vec2(u_scale));
	} else if (choice == 2) {
		distance_score = sdf_triangle_l(p, u_scale * 1.2);
	} else if (choice == 3) {
		distance_score = sdf_star_l(p, u_scale * 1.3, 0.45);
	} else {
		distance_score = sdf_hexagon_l(p, u_scale);
	}
	
	// MAGIC LINE CODES: abs() isolates the shell perimeter.
	// We subtract thickness so 0.0 is the exact center of the wire stroke.
	float line_surface = abs(distance_score) - u_line_thickness;
	
	// Draw a smooth line stroke matching our thickness limits
	float line_mask = smoothstep(u_edge_softness, 0.0, line_surface);
	
	return mix(u_color_bg, u_color_shape, line_mask);
}
"""


const SRC_BASIC_SHAPES: String = """
// Tweakable Uniforms that your framework will parse automatically
uniform float u_shape_type = 0.0; // @label Shape Selector | @min 0 | @max 4 | @sens 1
uniform vec2 u_position = vec2(0.0, 0.0); // @label Position Offset | @min -1 | @max 1 | @sens 0.01
uniform float u_scale = 0.35; // @label Shape Scale | @min 0.05 | @max 1.0 | @sens 0.01
uniform float u_rotation = 0.0; // @label Rotation | @min -3.1416 | @max 3.1416 | @sens 0.05
uniform float u_edge_softness = 0.01; // @label Edge Blur | @min 0.001 | @max 0.2 | @sens 0.001

uniform vec4 u_color_shape : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Shape Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_bg : source_color = vec4(0.02, 0.02, 0.05, 1.0); // @label Background Color | @min 0 | @max 1 | @sens 0.02

// Helper: 2D Rotation Matrix
vec2 shapes_rotate(vec2 p, float angle) {
	float s = sin(angle); float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// 1. Circle SDF
float sdf_circle(vec2 p, float r) { return length(p) - r; }

// 2. Box SDF
float sdf_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 3. Equilateral Triangle SDF
float sdf_triangle(vec2 p, float r) {
	float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

// 4. Five-Pointed Star SDF
float sdf_star(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.80901699437, -0.58778525229);
	vec2 k2 = vec2(-0.30901699437, 0.95105651629);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, r);
	vec2 pa = p - vec2(0.0, r);
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}

// 5. Hexagon SDF
float sdf_hexagon(vec2 p, float r) {
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

vec4 fx_shapes_static(vec2 uv) {
	// Center coordinates (-0.5 to 0.5) and apply user position slider offsets
	vec2 p = uv - 0.5 - u_position;
	
	// Apply user rotation uniform
	p = shapes_rotate(p, u_rotation);
	
	float distance_score = 0.0;
	int choice = int(floor(u_shape_type + 0.5));
	
	// Evaluate the correct math function based on the user's float selection
	if (choice == 0) {
		distance_score = sdf_circle(p, u_scale);
	} else if (choice == 1) {
		distance_score = sdf_box(p, vec2(u_scale));
	} else if (choice == 2) {
		distance_score = sdf_triangle(p, u_scale * 1.2);
	} else if (choice == 3) {
		distance_score = sdf_star(p, u_scale * 1.3, 0.45);
	} else {
		distance_score = sdf_hexagon(p, u_scale);
	}
	
	// Use smoothstep to give clean antialiasing or adjustable edge blurring
	float shape_mask = smoothstep(u_edge_softness, 0.0, distance_score);
	
	// Mix background and shape color smoothly
	return mix(u_color_bg, u_color_shape, shape_mask);
}
"""


const SRC_PLASMA_STATIC: String = """
uniform vec2 u_plasma_scale = vec2(4.0, 4.0); // @label Wave Scale | @min 1.0 | @max 16.0 | @sens 0.1
uniform float u_plasma_speed = 1.0; // @label Wave Speed | @min 0.0 | @max 4.0 | @sens 0.05
uniform float u_turbulence = 1.0; // @label Wave Complexity | @min 0.2 | @max 4.0 | @sens 0.05

uniform vec4 u_color_trough : source_color = vec4(0.02, 0.0, 0.1, 1.0); // @label Wave Trough | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_slope : source_color = vec4(0.1, 0.4, 0.8, 1.0); // @label Wave Slope | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_crest : source_color = vec4(0.0, 1.0, 0.9, 1.0); // @label Wave Crest | @min 0 | @max 1 | @sens 0.02

vec4 fx_plasma_static(vec2 uv) {
	vec2 p = (uv - 0.5) * u_plasma_scale;
	float t = u_time * u_plasma_speed;
	
	// Layer 1: Linear moving horizontal wave
	float v1 = sin(p.x * u_turbulence + t);
	
	// Layer 2: Moving angled wave
	float v2 = sin(u_turbulence * (p.y * cos(t * 0.33) + p.x * sin(t * 0.21)) + t);
	
	// Layer 3: Radial circular wave moving out from an animated center coordinate
	vec2 c_pos = p + vec2(sin(t * 0.4), cos(t * 0.35)) * 2.0;
	float v3 = sin(sqrt(dot(c_pos, c_pos)) * u_turbulence - t);
	
	// Consolidate into a smooth mathematical fluid field value (normalized roughly to 0.0 - 1.0)
	float plasma_field = (v1 + v2 + v3) / 3.0;
	plasma_field = plasma_field * 0.5 + 0.5;
	
	// Basic scalar color mixing across the wave elevations
	vec4 final_color = mix(u_color_trough, u_color_slope, smoothstep(0.0, 0.5, plasma_field));
	final_color = mix(final_color, u_color_crest, smoothstep(0.5, 1.0, plasma_field));
	
	return final_color;
}
"""
const SRC_PLASMA_COSINE: String = """
uniform vec2 u_plasma_scale = vec2(4.0, 4.0); // @label Wave Scale | @min 1.0 | @max 16.0 | @sens 0.1
uniform float u_plasma_speed = 1.0; // @label Wave Speed | @min 0.0 | @max 4.0 | @sens 0.05
uniform float u_turbulence = 1.0; // @label Wave Complexity | @min 0.2 | @max 4.0 | @sens 0.05
uniform float u_palette_frequency = 2.0; // @label Color Density | @min 0.5 | @max 6.0 | @sens 0.05
uniform float u_color_cycle_speed = 0.5; // @label Color Cycle Speed | @min 0 | @max 3 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.0, 0.33, 0.67, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

vec4 fx_plasma_cosine(vec2 uv) {
	vec2 p = (uv - 0.5) * u_plasma_scale;
	float t = u_time * u_plasma_speed;
	
	float v1 = sin(p.x * u_turbulence + t);
	float v2 = sin(u_turbulence * (p.y * cos(t * 0.33) + p.x * sin(t * 0.21)) + t);
	vec2 c_pos = p + vec2(sin(t * 0.4), cos(t * 0.35)) * 2.0;
	float v3 = sin(sqrt(dot(c_pos, c_pos)) * u_turbulence - t);
	
	float plasma_field = (v1 + v2 + v3) / 3.0;
	plasma_field = plasma_field * 0.5 + 0.5;
	
	// Drive color phases dynamically using the combined wave topology + color clock
	float color_phase = (plasma_field * u_palette_frequency) + (u_time * u_color_cycle_speed);
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * color_phase + u_color_d.rgb));
	
	return vec4(cos_color, 1.0);
}
"""
const SRC_PLASMA_CHRONO: String = """
uniform vec2 u_plasma_scale = vec2(4.0, 4.0); // @label Wave Scale | @min 1.0 | @max 16.0 | @sens 0.1
uniform float u_plasma_speed = 1.0; // @label Wave Speed | @min 0.0 | @max 4.0 | @sens 0.05
uniform float u_turbulence = 1.0; // @label Wave Complexity | @min 0.2 | @max 4.0 | @sens 0.05
uniform float u_color_morph_speed = 0.7; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_trough : source_color = vec4(0.02, 0.0, 0.1, 1.0); // @label Wave Trough | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_slope : source_color = vec4(0.1, 0.4, 0.8, 1.0); // @label Wave Slope | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_crest : source_color = vec4(0.0, 1.0, 0.9, 1.0); // @label Wave Crest | @min 0 | @max 1 | @sens 0.02

vec4 fx_plasma_chrono(vec2 uv) {
	vec2 p = (uv - 0.5) * u_plasma_scale;
	float t = u_time * u_plasma_speed;
	
	float v1 = sin(p.x * u_turbulence + t);
	float v2 = sin(u_turbulence * (p.y * cos(t * 0.33) + p.x * sin(t * 0.21)) + t);
	vec2 c_pos = p + vec2(sin(t * 0.4), cos(t * 0.35)) * 2.0;
	float v3 = sin(sqrt(dot(c_pos, c_pos)) * u_turbulence - t);
	
	float plasma_field = (v1 + v2 + v3) / 3.0;
	plasma_field = plasma_field * 0.5 + 0.5;
	
	// Continuous baseline interpolation swap factor
	float morph = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 morphing_trough = mix(u_color_trough, u_color_slope, morph);
	vec4 morphing_crest = mix(u_color_crest, u_color_trough, morph * 0.6);
	
	vec4 final_color = mix(morphing_trough, u_color_slope, smoothstep(0.0, 0.5, plasma_field));
	final_color = mix(final_color, morphing_crest, smoothstep(0.5, 1.0, plasma_field));
	
	return final_color;
}
"""
const SRC_PLASMA_CYBER: String = """
uniform vec2 u_plasma_scale = vec2(4.0, 4.0); // @label Wave Scale | @min 1.0 | @max 16.0 | @sens 0.1
uniform float u_plasma_speed = 1.0; // @label Wave Speed | @min 0.0 | @max 4.0 | @sens 0.05
uniform float u_turbulence = 1.0; // @label Wave Complexity | @min 0.2 | @max 4.0 | @sens 0.05
uniform float u_vein_density = 14.0; // @label Pulse Density | @min 4.0 | @max 28.0 | @sens 0.5
uniform float u_glow_sharpness = 0.84; // @label Glow Sharpness | @min 0.5 | @max 0.99 | @sens 0.01

uniform vec4 u_color_base : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Void Base | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_glow : source_color = vec4(0.0, 0.2, 0.15, 1.0); // @label Ambient Light | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(0.3, 1.0, 0.0, 1.0); // @label Neon Filament | @min 0 | @max 1 | @sens 0.02

vec4 fx_plasma_cyber(vec2 uv) {
	vec2 p = (uv - 0.5) * u_plasma_scale;
	float t = u_time * u_plasma_speed;
	
	float v1 = sin(p.x * u_turbulence + t);
	float v2 = sin(u_turbulence * (p.y * cos(t * 0.33) + p.x * sin(t * 0.21)) + t);
	vec2 c_pos = p + vec2(sin(t * 0.4), cos(t * 0.35)) * 2.0;
	float v3 = sin(sqrt(dot(c_pos, c_pos)) * u_turbulence - t);
	
	float plasma_field = (v1 + v2 + v3) / 3.0;
	plasma_field = plasma_field * 0.5 + 0.5;
	
	// Compress the plasma terrain into repeating energy ring ripples
	float pulse = sin(plasma_field * u_vein_density - u_time * 2.0) * 0.5 + 0.5;
	float circuits = smoothstep(u_glow_sharpness, u_glow_sharpness + 0.05, pulse);
	
	// Layer an ambient topographical glow underneath the filaments
	vec4 dynamic_bg = mix(u_color_base, u_color_glow, plasma_field);
	
	return mix(dynamic_bg, u_pattern_color, clamp(circuits, 0.0, 1.0));
}
"""


const SRC_GYROID_STATIC: String = """
uniform vec2 u_maze_scale = vec2(6.0, 6.0); // @label Maze Scale | @min 1.0 | @max 24.0 | @sens 0.1
uniform float u_complexity = 1.0; // @label Labyrinth Folding | @min 0.5 | @max 4.0 | @sens 0.05
uniform float u_morph_speed = 0.3; // @label Morph Speed | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_wall_thickness = 0.25; // @label Wall Thickness | @min 0.05 | @max 0.6 | @sens 0.01

uniform vec4 u_color_background : source_color = vec4(0.02, 0.03, 0.05, 1.0); // @label Floor Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_walls : source_color = vec4(0.4, 0.2, 0.6, 1.0); // @label Wall Core Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_accents : source_color = vec4(0.0, 0.9, 0.6, 1.0); // @label Ridge Highlight | @min 0 | @max 1 | @sens 0.02

vec4 fx_gyroid_static(vec2 uv) {
	// Center space and apply user scaling
	vec2 p = (uv - 0.5) * u_maze_scale;
	
	// Create an artificial 3D coordinate system using time to drive the Z axis
	float z_time = u_time * u_morph_speed;
	
	// Precalculate trigonometric space transformations
	vec3 coord = vec3(p.x, p.y, z_time);
	vec3 s = sin(coord * u_complexity);
	vec3 c = cos(coord * u_complexity);
	
	// The fundamental Gyroid Surface Formula: sin(x)*cos(y) + sin(y)*cos(z) + sin(z)*cos(x)
	float gyroid_field = (s.x * c.y) + (s.y * c.z) + (s.z * c.x);
	
	// Normalize the field score down to an absolute value for sharp corridor edges
	float field_abs = abs(gyroid_field);
	
	// Define the structural walls using the user's thickness configuration
	float wall_mask = smoothstep(u_wall_thickness + 0.05, u_wall_thickness, field_abs);
	
	// EXTRACT INTERNAL DATA: Generate sharp ridges down the direct center of the walls
	float ridge_mask = smoothstep(0.08, 0.0, field_abs) * wall_mask;
	
	// Base layer blending
	vec4 final_color = mix(u_color_background, u_color_walls, wall_mask);
	
	// Overlay structural highlights using the internal ridge vectors
	final_color = mix(final_color, u_color_accents, ridge_mask);
	
	// Add depth shading based on proximity to the corridor center
	return final_color * (1.0 - field_abs * 0.2);
}
"""
const SRC_VORONOI_STATIC: String = """
uniform vec2 u_cell_scale = vec2(5.0, 5.0); // @label Cell Scale | @min 1.0 | @max 20.0 | @sens 0.1
uniform float u_jitter = 1.0; // @label Chaos / Jitter | @min 0.0 | @max 1.0 | @sens 0.05
uniform float u_cell_speed = 0.5; // @label Cell Agitation | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_border_thickness = 0.04; // @label Border Thickness | @min 0.01 | @max 0.2 | @sens 0.005

uniform vec4 u_color_cell_core : source_color = vec4(0.05, 0.25, 0.4, 1.0); // @label Cell Core Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_cell_edge : source_color = vec4(0.1, 0.6, 0.7, 1.0); // @label Cell Slopes | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_border : source_color = vec4(1.0, 0.95, 0.8, 1.0); // @label Crystal Borders | @min 0 | @max 1 | @sens 0.02

// Cellular hash to place points randomly inside grids
vec2 voronoi_hash2d(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Custom 2-distance Voronoi computation engine
void evaluate_voronoi(vec2 p, out float out_d1, out float out_d2) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	
	float d1 = 8.0;
	float d2 = 8.0;
	
	// Loop through a 3x3 neighborhood of cells to check adjacent points
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = voronoi_hash2d(n + g);
			
			// Animate the points inside their grids
			o = 0.5 + 0.5 * sin(u_time * u_cell_speed + o * 6.2831);
			
			// Vector pointing from pixel to the animated feature point
			vec2 r = g + o * u_jitter - f;
			float d = dot(r, r); // Using squared distance for efficiency and look
			
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	
	// Return true Euclidean approximations
	out_d1 = sqrt(d1);
	out_d2 = sqrt(d2);
}

vec4 fx_voronoi_static(vec2 uv) {
	vec2 st = uv * u_cell_scale;
	
	float d1, d2;
	evaluate_voronoi(st, d1, d2);
	
	// Base lighting slope out from the absolute center point
	vec4 base_crystal = mix(u_color_cell_core, u_color_cell_edge, smoothstep(0.0, 0.7, d1));
	
	// Extract internal data: d2 - d1 isolates the razor-thin border lines between cells
	float crystal_borders = d2 - d1;
	float border_mask = smoothstep(u_border_thickness, 0.0, crystal_borders);
	
	// Overlay crystal border lines
	vec4 final_mix = mix(base_crystal, u_color_border, border_mask);
	
	// Dynamic faceted shading across the cells
	return final_mix * (0.4 + 0.6 * smoothstep(0.0, 0.8, crystal_borders));
}
"""

const SRC_VORONOI_COSINE: String = """
uniform vec2 u_cell_scale = vec2(5.0, 5.0); // @label Cell Scale | @min 1.0 | @max 20.0 | @sens 0.1
uniform float u_jitter = 1.0; // @label Chaos / Jitter | @min 0.0 | @max 1.0 | @sens 0.05
uniform float u_cell_speed = 0.5; // @label Cell Agitation | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_palette_frequency = 1.5; // @label Color Density | @min 0.2 | @max 5.0 | @sens 0.05
uniform float u_color_cycle_speed = 0.4; // @label Color Cycle Speed | @min 0 | @max 3 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.0, 0.33, 0.67, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

vec2 voronoi_hash2d(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void evaluate_voronoi(vec2 p, out float out_d1, out float out_d2) {
	vec2 n = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = voronoi_hash2d(n + g);
			o = 0.5 + 0.5 * sin(u_time * u_cell_speed + o * 6.2831);
			vec2 r = g + o * u_jitter - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	out_d1 = sqrt(d1); out_d2 = sqrt(d2);
}

vec4 fx_voronoi_cosine(vec2 uv) {
	vec2 st = uv * u_cell_scale;
	float d1, d2;
	evaluate_voronoi(st, d1, d2);
	
	// Use the cell distance radius and time to cycle the color spectrum
	float t = (d1 * u_palette_frequency) + (u_time * u_color_cycle_speed);
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * t + u_color_d.rgb));
	
	// Add cell shading structure by darkening cell boundaries slightly
	float crystal_borders = d2 - d1;
	return vec4(cos_color, 1.0) * (0.5 + 0.5 * smoothstep(0.0, 0.4, crystal_borders));
}
"""
const SRC_VORONOI_CHRONO: String = """
uniform vec2 u_cell_scale = vec2(5.0, 5.0); // @label Cell Scale | @min 1.0 | @max 20.0 | @sens 0.1
uniform float u_jitter = 1.0; // @label Chaos / Jitter | @min 0.0 | @max 1.0 | @sens 0.05
uniform float u_cell_speed = 0.5; // @label Cell Agitation | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_border_thickness = 0.04; // @label Border Thickness | @min 0.01 | @max 0.2 | @sens 0.005
uniform float u_color_morph_speed = 0.6; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_cell_core : source_color = vec4(0.05, 0.25, 0.4, 1.0); // @label Cell Core Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_cell_edge : source_color = vec4(0.1, 0.6, 0.7, 1.0); // @label Cell Slopes | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_border : source_color = vec4(1.0, 0.95, 0.8, 1.0); // @label Crystal Borders | @min 0 | @max 1 | @sens 0.02

vec2 voronoi_hash2d(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void evaluate_voronoi(vec2 p, out float out_d1, out float out_d2) {
	vec2 n = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = voronoi_hash2d(n + g);
			o = 0.5 + 0.5 * sin(u_time * u_cell_speed + o * 6.2831);
			vec2 r = g + o * u_jitter - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	out_d1 = sqrt(d1); out_d2 = sqrt(d2);
}

vec4 fx_voronoi_chrono(vec2 uv) {
	vec2 st = uv * u_cell_scale;
	float d1, d2;
	evaluate_voronoi(st, d1, d2);
	
	// Create an oscillating timeline shift factor for the color parameters
	float shift = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 morphing_core = mix(u_color_cell_core, u_color_cell_edge, shift);
	vec4 morphing_edge = mix(u_color_cell_edge, u_color_border, shift * 0.4);
	
	vec4 base_crystal = mix(morphing_core, morphing_edge, smoothstep(0.0, 0.7, d1));
	
	float crystal_borders = d2 - d1;
	float border_mask = smoothstep(u_border_thickness, 0.0, crystal_borders);
	vec4 final_mix = mix(base_crystal, u_color_border, border_mask);
	
	return final_mix * (0.4 + 0.6 * smoothstep(0.0, 0.8, crystal_borders));
}
"""
const SRC_VORONOI_CYBER: String = """
uniform vec2 u_cell_scale = vec2(5.0, 5.0); // @label Cell Scale | @min 1.0 | @max 20.0 | @sens 0.1
uniform float u_jitter = 1.0; // @label Chaos / Jitter | @min 0.0 | @max 1.0 | @sens 0.05
uniform float u_cell_speed = 0.5; // @label Cell Agitation | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_vein_density = 10.0; // @label Pulse Density | @min 4.0 | @max 25.0 | @sens 0.5
uniform float u_glow_sharpness = 0.80; // @label Glow Sharpness | @min 0.5 | @max 0.99 | @sens 0.01

uniform vec4 u_color_base : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Cell Void Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_glow : source_color = vec4(0.2, 0.0, 0.1, 1.0); // @label Plate Radiance | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(1.0, 0.0, 0.4, 1.0); // @label Filament Laser | @min 0 | @max 1 | @sens 0.02

vec2 voronoi_hash2d(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void evaluate_voronoi(vec2 p, out float out_d1, out float out_d2) {
	vec2 n = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = voronoi_hash2d(n + g);
			o = 0.5 + 0.5 * sin(u_time * u_cell_speed + o * 6.2831);
			vec2 r = g + o * u_jitter - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	out_d1 = sqrt(d1); out_d2 = sqrt(d2);
}

vec4 fx_voronoi_cyber(vec2 uv) {
	vec2 st = uv * u_cell_scale;
	float d1, d2;
	evaluate_voronoi(st, d1, d2);
	
	float crystal_borders = d2 - d1;
	
	// Create an expanding energy pulse radiating outward from the borders
	float pulse = sin(crystal_borders * u_vein_density - u_time * 2.0) * 0.5 + 0.5;
	float grid_lines = smoothstep(u_glow_sharpness, u_glow_sharpness + 0.08, pulse);
	
	// Give an ambient radioactive look hugging the edges of plates
	vec4 dynamic_bg = mix(u_color_base, u_color_glow, smoothstep(0.5, 0.0, crystal_borders));
	
	// Fade the lines inside the exact geometric cores of the plates
	float filament_mask = grid_lines * smoothstep(0.02, 0.15, crystal_borders);
	
	return mix(dynamic_bg, u_pattern_color, clamp(filament_mask, 0.0, 1.0));
}
"""


const SRC_FBM: String = """
uniform vec2 u_warp_frequency = vec2(2.5, 2.5); // @label Warp Frequency | @min 0.1 | @max 12 | @sens 0.05
uniform float u_warp_strength = 1.1; // @label Warp Strength | @min 0 | @max 4 | @sens 0.05
uniform float u_noise_detail = 4.0; // @label Noise Detail | @min 1 | @max 5 | @sens 1
uniform float u_flow_speed = 0.4; // @label Flow Speed | @min 0 | @max 3 | @sens 0.05

// FOUR DISTINCT COLOR SLOTS EXPOSED TO THE USER
uniform vec4 u_color_base : source_color = vec4(0.02, 0.02, 0.05, 1.0); // @label Base Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_warp_q : source_color = vec4(0.12, 0.0, 0.22, 1.0); // @label Distortion Color A | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_warp_r : source_color = vec4(0.0, 0.5, 0.5, 1.0); // @label Distortion Color B | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(0.1, 0.7, 0.9, 1.0); // @label Highlight Color | @min 0 | @max 1 | @sens 0.02

float fbm_hash2d(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float fbm_value_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fbm_hash2d(i + vec2(0.0, 0.0)), fbm_hash2d(i + vec2(1.0, 0.0)), u.x),
			   mix(fbm_hash2d(i + vec2(0.0, 1.0)), fbm_hash2d(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm_octaves(vec2 p) {
	float value = 0.0; float amplitude = 0.5; float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		if (float(i) >= u_noise_detail) break;
		value += amplitude * fbm_value_noise(p * frequency);
		frequency *= 2.0; amplitude *= 0.5;
	}
	return value;
}
vec4 fx_fbm_static(vec2 uv) {
	vec2 st = uv * u_warp_frequency;
	float scaled_time = u_time * u_flow_speed;
	
	// Extracting the data layers
	vec2 q = vec2(fbm_octaves(st + vec2(scaled_time * 0.2)), fbm_octaves(st + vec2(5.2, 1.3) + vec2(scaled_time * 0.15)));
	vec2 r = vec2(fbm_octaves(st + u_warp_strength * q + vec2(1.7, 9.2) + vec2(scaled_time * 0.3)), fbm_octaves(st + u_warp_strength * q + vec2(8.3, 2.8) + vec2(scaled_time * 0.05)));
	float final_field_math = fbm_octaves(st + u_warp_strength * r);
	
	// 1. Core mix: Blends Base Color into Warp Q color based on the magnitude of the first warp layer
	vec4 dynamic_color = mix(u_color_base, u_color_warp_q, clamp(length(q), 0.0, 1.0));
	
	// 2. Secondary layer mix: Infuses Warp R color based on the directional variance (angle) of the secondary veins
	float angle_factor = (atan(r.y, r.x) + 3.14159) / 6.28318; // normalize angle to 0.0 - 1.0
	dynamic_color = mix(dynamic_color, u_color_warp_r, clamp(angle_factor * length(r), 0.0, 1.0));
	
	// 3. Final field layer: Layers the Pattern/Highlight color using the overall scalar intensity
	vec4 final_mix = mix(dynamic_color, u_pattern_color, final_field_math);
	
	// Maintain your original brightness multiplier shading curve
	return final_mix * (final_field_math * 1.5 + 0.3);
}
"""

const SRC_GYROID_COSINE: String = """
uniform vec2 u_maze_scale = vec2(6.0, 6.0); // @label Maze Scale | @min 1.0 | @max 24.0 | @sens 0.1
uniform float u_complexity = 1.0; // @label Labyrinth Folding | @min 0.5 | @max 4.0 | @sens 0.05
uniform float u_morph_speed = 0.3; // @label Morph Speed | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_palette_frequency = 1.5; // @label Color Density | @min 0.2 | @max 5.0 | @sens 0.05
uniform float u_color_cycle_speed = 0.4; // @label Color Cycle Speed | @min 0 | @max 3 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.3, 0.1, 0.5, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

vec4 fx_gyroid_cosine(vec2 uv) {
	vec2 p = (uv - 0.5) * u_maze_scale;
	float z_time = u_time * u_morph_speed;
	
	vec3 coord = vec3(p.x, p.y, z_time);
	float gyroid_field = (sin(coord.x*u_complexity) * cos(coord.y*u_complexity)) + 
	                     (sin(coord.y*u_complexity) * cos(coord.z)) + 
	                     (sin(coord.z) * cos(coord.x*u_complexity));
	
	float field_abs = abs(gyroid_field);
	
	// Drive the cosine color phase using the spatial maze depth combined with independent color time
	float t = (field_abs * u_palette_frequency) + (u_time * u_color_cycle_speed);
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * t + u_color_d.rgb));
	
	// Darken the very center of deep corridors for structural depth shadow
	return vec4(cos_color, 1.0) * (1.0 - smoothstep(1.2, 2.0, field_abs) * 0.4);
}
"""
const SRC_GYROID_CHRONO: String = """
uniform vec2 u_maze_scale = vec2(6.0, 6.0); // @label Maze Scale | @min 1.0 | @max 24.0 | @sens 0.1
uniform float u_complexity = 1.0; // @label Labyrinth Folding | @min 0.5 | @max 4.0 | @sens 0.05
uniform float u_morph_speed = 0.3; // @label Morph Speed | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_wall_thickness = 0.25; // @label Wall Thickness | @min 0.05 | @max 0.6 | @sens 0.01
uniform float u_color_morph_speed = 0.6; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_background : source_color = vec4(0.01, 0.02, 0.05, 1.0); // @label Floor Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_walls : source_color = vec4(0.8, 0.2, 0.1, 1.0); // @label Wall Core Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_accents : source_color = vec4(1.0, 0.7, 0.0, 1.0); // @label Ridge Highlight | @min 0 | @max 1 | @sens 0.02

vec4 fx_gyroid_chrono(vec2 uv) {
	vec2 p = (uv - 0.5) * u_maze_scale;
	float z_time = u_time * u_morph_speed;
	
	vec3 coord = vec3(p.x, p.y, z_time);
	float gyroid_field = (sin(coord.x*u_complexity) * cos(coord.y*u_complexity)) + 
	                     (sin(coord.y*u_complexity) * cos(coord.z)) + 
	                     (sin(coord.z) * cos(coord.x*u_complexity));
	
	float field_abs = abs(gyroid_field);
	float wall_mask = smoothstep(u_wall_thickness + 0.05, u_wall_thickness, field_abs);
	float ridge_mask = smoothstep(0.08, 0.0, field_abs) * wall_mask;
	
	// Create a continuous color blending timeline factor
	float shift = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 morphing_walls = mix(u_color_walls, u_color_accents, shift);
	vec4 morphing_accents = mix(u_color_accents, u_color_background, shift * 0.5);
	
	vec4 final_color = mix(u_color_background, morphing_walls, wall_mask);
	final_color = mix(final_color, morphing_accents, ridge_mask);
	
	return final_color * (1.0 - field_abs * 0.2);
}
"""
const SRC_GYROID_CYBER: String = """
uniform vec2 u_maze_scale = vec2(6.0, 6.0); // @label Maze Scale | @min 1.0 | @max 24.0 | @sens 0.1
uniform float u_complexity = 1.0; // @label Labyrinth Folding | @min 0.5 | @max 4.0 | @sens 0.05
uniform float u_morph_speed = 0.3; // @label Morph Speed | @min 0.0 | @max 3.0 | @sens 0.05
uniform float u_vein_density = 15.0; // @label Vein Density | @min 4 | @max 35 | @sens 0.5
uniform float u_glow_sharpness = 0.82; // @label Glow Sharpness | @min 0.5 | @max 0.99 | @sens 0.01

uniform vec4 u_color_base : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Void Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_glow : source_color = vec4(0.1, 0.0, 0.25, 1.0); // @label Ambient Glow | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(0.0, 1.0, 0.5, 1.0); // @label Laser Filament | @min 0 | @max 1 | @sens 0.02

vec4 fx_gyroid_cyber(vec2 uv) {
	vec2 p = (uv - 0.5) * u_maze_scale;
	float z_time = u_time * u_morph_speed;
	
	vec3 coord = vec3(p.x, p.y, z_time);
	float gyroid_field = (sin(coord.x*u_complexity) * cos(coord.y*u_complexity)) + 
	                     (sin(coord.y*u_complexity) * cos(coord.z)) + 
	                     (sin(coord.z) * cos(coord.x*u_complexity));
	
	float field_abs = abs(gyroid_field);
	
	// Slice the terrain into recursive circuit ring frequencies
	float laser_pulse = sin(field_abs * u_vein_density - u_time * 1.5) * 0.5 + 0.5;
	float circuits = smoothstep(u_glow_sharpness, u_glow_sharpness + 0.06, laser_pulse);
	
	// Create ambient light bands hugging the structural corridors
	vec4 dynamic_bg = mix(u_color_base, u_color_glow, smoothstep(1.5, 0.0, field_abs));
	
	// Mask the laser filaments so they get weaker/thinner inside the ultra-deep corridor nodes
	float laser_mask = circuits * smoothstep(2.0, 0.2, field_abs);
	
	return mix(dynamic_bg, u_pattern_color, clamp(laser_mask, 0.0, 1.0));
}
"""


const SRC_FBM_COSINE: String = """
uniform vec2 u_warp_frequency = vec2(2.5, 2.5); // @label Warp Frequency | @min 0.1 | @max 12 | @sens 0.05
uniform float u_warp_strength = 1.1; // @label Warp Strength | @min 0 | @max 4 | @sens 0.05
uniform float u_noise_detail = 4.0; // @label Noise Detail | @min 1 | @max 5 | @sens 1
uniform float u_flow_speed = 0.4; // @label Flow Speed | @min 0 | @max 3 | @sens 0.05
uniform float u_palette_frequency = 1.0; // @label Color Density | @min 0.2 | @max 5.0 | @sens 0.05

uniform vec4 u_color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Center | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0); // @label Wave Amplitude | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0); // @label Wave Frequency | @min 0 | @max 2 | @sens 0.02
uniform vec4 u_color_d : source_color = vec4(0.0, 0.33, 0.67, 1.0); // @label Wave Phase | @min 0 | @max 1 | @sens 0.02

float fbm_hash2d(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float fbm_value_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fbm_hash2d(i + vec2(0.0, 0.0)), fbm_hash2d(i + vec2(1.0, 0.0)), u.x),
			   mix(fbm_hash2d(i + vec2(0.0, 1.0)), fbm_hash2d(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm_octaves(vec2 p) {
	float value = 0.0; float amplitude = 0.5; float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		if (float(i) >= u_noise_detail) break;
		value += amplitude * fbm_value_noise(p * frequency);
		frequency *= 2.0; amplitude *= 0.5;
	}
	return value;
}
vec4 fx_fbm_cosine(vec2 uv) {
	vec2 st = uv * u_warp_frequency;
	float scaled_time = u_time * u_flow_speed;
	vec2 q = vec2(fbm_octaves(st + vec2(scaled_time * 0.2)), fbm_octaves(st + vec2(5.2, 1.3) + vec2(scaled_time * 0.15)));
	vec2 r = vec2(fbm_octaves(st + u_warp_strength * q + vec2(1.7, 9.2) + vec2(scaled_time * 0.3)), fbm_octaves(st + u_warp_strength * q + vec2(8.3, 2.8) + vec2(scaled_time * 0.05)));
	float final_field_math = fbm_octaves(st + u_warp_strength * r);
	
	// Drive the cyclical cosine phase using a mix of the field map and the structural stretch
	float t = (final_field_math + length(q) * 0.3) * u_palette_frequency;
	vec3 cos_color = u_color_a.rgb + u_color_b.rgb * cos(6.28318 * (u_color_c.rgb * t + u_color_d.rgb));
	
	return vec4(cos_color, 1.0) * (final_field_math * 1.5 + 0.3);
}
"""

const SRC_FBM_CYBER: String = """
uniform vec2 u_warp_frequency = vec2(2.5, 2.5); // @label Warp Frequency | @min 0.1 | @max 12 | @sens 0.05
uniform float u_warp_strength = 1.1; // @label Warp Strength | @min 0 | @max 4 | @sens 0.05
uniform float u_noise_detail = 4.0; // @label Noise Detail | @min 1 | @max 5 | @sens 1
uniform float u_flow_speed = 0.4; // @label Flow Speed | @min 0 | @max 3 | @sens 0.05
uniform float u_vein_density = 12.0; // @label Vein Density | @min 4 | @max 30 | @sens 0.5
uniform float u_glow_sharpness = 0.85; // @label Glow Sharpness | @min 0.5 | @max 0.99 | @sens 0.01

uniform vec4 u_color_base : source_color = vec4(0.01, 0.01, 0.03, 1.0); // @label Background Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_warp_q : source_color = vec4(0.05, 0.0, 0.15, 1.0); // @label Nebula Tint | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(0.0, 1.0, 0.8, 1.0); // @label Neon Vein Color | @min 0 | @max 1 | @sens 0.02

float fbm_hash2d(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float fbm_value_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fbm_hash2d(i + vec2(0.0, 0.0)), fbm_hash2d(i + vec2(1.0, 0.0)), u.x),
			   mix(fbm_hash2d(i + vec2(0.0, 1.0)), fbm_hash2d(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm_octaves(vec2 p) {
	float value = 0.0; float amplitude = 0.5; float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		if (float(i) >= u_noise_detail) break;
		value += amplitude * fbm_value_noise(p * frequency);
		frequency *= 2.0; amplitude *= 0.5;
	}
	return value;
}
vec4 fx_fbm_cyber(vec2 uv) {
	vec2 st = uv * u_warp_frequency;
	float scaled_time = u_time * u_flow_speed;
	
	vec2 q = vec2(fbm_octaves(st + vec2(scaled_time * 0.2)), fbm_octaves(st + vec2(5.2, 1.3) + vec2(scaled_time * 0.15)));
	vec2 r = vec2(fbm_octaves(st + u_warp_strength * q + vec2(1.7, 9.2) + vec2(scaled_time * 0.3)), fbm_octaves(st + u_warp_strength * q + vec2(8.3, 2.8) + vec2(scaled_time * 0.05)));
	float final_field_math = fbm_octaves(st + u_warp_strength * r);
	
	// Create sharp electrical rings using a high-frequency sine wave driven by time
	float pulse = sin(final_field_math * u_vein_density + u_time * 0.5) * 0.5 + 0.5;
	
	// Smoothstep clamps it into highly defined glowing neon borders
	float veins = smoothstep(u_glow_sharpness, u_glow_sharpness + 0.08, pulse);
	
	// Deep cosmic background mix
	vec4 dynamic_bg = mix(u_color_base, u_color_warp_q, final_field_math);
	
	// Make veins brighter in areas where space is stretched heavily by r
	float vein_mask = veins * (length(r) * 1.2 + 0.2);
	vec4 final_mix = mix(dynamic_bg, u_pattern_color, clamp(vein_mask, 0.0, 1.0));
	
	// Subtle background topography lighting
	return final_mix + (final_field_math * u_color_warp_q * 0.3);
}
"""


const SRC_FBM_CHRONO: String = """
uniform vec2 u_warp_frequency = vec2(2.5, 2.5); // @label Warp Frequency | @min 0.1 | @max 12 | @sens 0.05
uniform float u_warp_strength = 1.1; // @label Warp Strength | @min 0 | @max 4 | @sens 0.05
uniform float u_noise_detail = 4.0; // @label Noise Detail | @min 1 | @max 5 | @sens 1
uniform float u_flow_speed = 0.4; // @label Flow Speed | @min 0 | @max 3 | @sens 0.05
uniform float u_color_morph_speed = 0.5; // @label Color Morph Speed | @min 0 | @max 4 | @sens 0.05

uniform vec4 u_color_base : source_color = vec4(0.02, 0.02, 0.05, 1.0); // @label Base Color | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_warp_q : source_color = vec4(0.12, 0.0, 0.22, 1.0); // @label Distortion Color A | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_color_warp_r : source_color = vec4(0.0, 0.5, 0.5, 1.0); // @label Distortion Color B | @min 0 | @max 1 | @sens 0.02
uniform vec4 u_pattern_color : source_color = vec4(0.1, 0.7, 0.9, 1.0); // @label Highlight Color | @min 0 | @max 1 | @sens 0.02

float fbm_hash2d(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float fbm_value_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fbm_hash2d(i + vec2(0.0, 0.0)), fbm_hash2d(i + vec2(1.0, 0.0)), u.x),
			   mix(fbm_hash2d(i + vec2(0.0, 1.0)), fbm_hash2d(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm_octaves(vec2 p) {
	float value = 0.0; float amplitude = 0.5; float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		if (float(i) >= u_noise_detail) break;
		value += amplitude * fbm_value_noise(p * frequency);
		frequency *= 2.0; amplitude *= 0.5;
	}
	return value;
}
vec4 fx_fbm_chrono(vec2 uv) {
	vec2 st = uv * u_warp_frequency;
	float scaled_time = u_time * u_flow_speed;
	vec2 q = vec2(fbm_octaves(st + vec2(scaled_time * 0.2)), fbm_octaves(st + vec2(5.2, 1.3) + vec2(scaled_time * 0.15)));
	vec2 r = vec2(fbm_octaves(st + u_warp_strength * q + vec2(1.7, 9.2) + vec2(scaled_time * 0.3)), fbm_octaves(st + u_warp_strength * q + vec2(8.3, 2.8) + vec2(scaled_time * 0.05)));
	float final_field_math = fbm_octaves(st + u_warp_strength * r);
	
	// Cycle colors over time independently of pattern flow
	float time_shift = sin(u_time * u_color_morph_speed) * 0.5 + 0.5;
	vec4 evolving_base = mix(u_color_base, u_color_warp_q, time_shift);
	vec4 evolving_warp = mix(u_color_warp_r, u_color_base, time_shift);
	
	vec4 dynamic_color = mix(evolving_base, evolving_warp, clamp(length(q), 0.0, 1.0));
	float angle_factor = (atan(r.y, r.x) + 3.14159) / 6.28318;
	dynamic_color = mix(dynamic_color, u_color_warp_r, clamp(angle_factor * length(r), 0.0, 1.0));
	
	vec4 final_mix = mix(dynamic_color, u_pattern_color, final_field_math);
	return final_mix * (final_field_math * 1.5 + 0.3);
}
"""


const SRC_KALEIDOSCOPE: String = """
uniform float u_segments = 6.0; // @label Slides | @min 1 | @max 32 | @sens 1
uniform float u_rotation_speed = 0.2; // @label Rotation Speed | @min -2 | @max 2 | @sens 0.05

vec2 fx_kaleidoscope(vec2 uv_in) {
	vec2 uv = uv_in - 0.5;
	float r = length(uv);
	float a = atan(uv.y, uv.x) + (u_time * u_rotation_speed);
	float angle_step = 2.0 * 3.14159265 / max(u_segments, 1.0);
	a = mod(a, angle_step);
	a = abs(a - angle_step * 0.5);
	return vec2(cos(a), sin(a)) * r + 0.5;
}
"""

const SRC_SWIRL: String = """
uniform vec2 u_center = vec2(0.5, 0.5); // @label Center | @min 0 | @max 1 | @sens 0.01
uniform float u_radius = 0.5; // @label Radius | @min 0.05 | @max 1.5 | @sens 0.02
uniform float u_strength = 3.0; // @label Twist Strength | @min -12 | @max 12 | @sens 0.25
uniform float u_rotation_speed = 0.0; // @label Rotation Speed | @min -2 | @max 2 | @sens 0.05

vec2 fx_swirl(vec2 uv) {
	vec2 p = uv - u_center;
	float falloff = 1.0 - smoothstep(0.0, u_radius, length(p));
	float ang = u_strength * falloff + u_time * u_rotation_speed;
	float s = sin(ang);
	float c = cos(ang);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y) + u_center;
}
"""

const SRC_EDGE_GLOW: String = """
uniform float u_edge_threshold = 0.15; // @label Edge Threshold | @min 0 | @max 1 | @sens 0.01
uniform float u_glow_intensity = 2.5; // @label Glow Intensity | @min 0 | @max 8 | @sens 0.1
uniform vec2 u_step_offset = vec2(0.003, 0.003); // @label Step Offset | @min 0.0005 | @max 0.02 | @sens 0.0005
uniform float u_cel_bands = 5.0; // @label Cel Shade Bands | @min 2.0 | @max 12.0 | @sens 1.0

vec3 quantize_cel(vec3 color, float bands) {
	return floor(color * bands) / bands;
}

vec4 fx_edge_glow(vec2 uv) {
	vec4 center_color = texture(u_warped_texture, uv);
	float c = (center_color.r + center_color.g + center_color.b) / 3.0;
	
	float left = texture(u_warped_texture, uv - vec2(u_step_offset.x, 0.0)).g;
	float right = texture(u_warped_texture, uv + vec2(u_step_offset.x, 0.0)).g;
	float up = texture(u_warped_texture, uv - vec2(0.0, u_step_offset.y)).g;
	float down = texture(u_warped_texture, uv + vec2(0.0, u_step_offset.y)).g;
	
	float edge_delta = abs(c - left) + abs(c - right) + abs(c - up) + abs(c - down);
	float edge_mask = smoothstep(u_edge_threshold, u_edge_threshold + 0.1, edge_delta);
	vec3 glowing_borders = center_color.rgb * edge_mask * u_glow_intensity;
	
	vec3 raw_composite = center_color.rgb + glowing_borders;
	vec3 cel_shaded = quantize_cel(raw_composite, u_cel_bands);
	
	return vec4(cel_shaded, center_color.a);
}
"""
