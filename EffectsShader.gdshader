shader_type canvas_item;

// =============================================================================
// FREE SHADER LAB — MasterShader.gdshader
// =============================================================================

// --- TIME & SYNC ---
uniform float manual_time = 0.0;
uniform float sync_to_loop : hint_range(0.0, 1.0, 1.0) = 0.0;

// --- PRE-KALEIDOSCOPE ROTATION ---
uniform float pre_rotation_angle : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float pre_rotation_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;

// --- PINWHEEL ---
uniform float pinwheel_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float pinwheel_sides    : hint_range(2.0, 16.0, 1.0) = 6.0;
uniform float pinwheel_twist    : hint_range(-3.14159, 3.14159, 0.01) = 0.5;
uniform float pinwheel_zoom     : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float pinwheel_speed    : hint_range(-2.0, 2.0, 0.01) = 0.0;


// --- KALEIDOSCOPE ---
uniform float kaleido_sides : hint_range(1.0, 16.0, 1.0) = 1.0;

// --- POST ROTATION ---
uniform float u_rotation : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float post_rotation_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;

// --- GEOMETRIC FOLD ---
uniform float fold_number : hint_range(0.0, 8.0, 1.0) = 0.0;
uniform float fold_zoom : hint_range(0.1, 10.0, 0.1) = 1.0;
uniform float fold_rot_speed : hint_range(-5.0, 5.0, 0.01) = 0.0;

// --- HEX TILE ---
uniform float hex_scale : hint_range(1.0, 10.0, 1.0) = 1.0;
uniform float hex_rot_speed : hint_range(-5.0, 5.0, 0.01) = 0.0;

// --- SWIRL ---
uniform float swirl_strength : hint_range(0.0, 10.0, 0.1) = 0.0;
uniform float swirl_speed : hint_range(-5.0, 5.0, 0.01) = 0.0;

// --- WAVE ---
uniform float wave_amplitude : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float wave_frequency : hint_range(1.0, 20.0, 1.0) = 10.0;
uniform float wave_speed : hint_range(-5.0, 5.0, 0.01) = 1.0;

// --- RIPPLE ---
uniform float ripple_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float ripple_frequency : hint_range(1.0, 20.0, 1.0) = 8.0;
uniform float ripple_speed : hint_range(-5.0, 5.0, 0.01) = 1.0;

// --- FISHEYE ---
uniform float fisheye : hint_range(-1.0, 1.0, 0.01) = 0.0;

// --- POINCARE WARP ---
uniform float poincare_warp : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- HYPERBOLIC BEND ---
uniform float hyperbolic_bend : hint_range(0.0, 3.0, 0.001) = 0.0;

// --- VORTEX LATTICE ---
uniform float vortex_density : hint_range(0.0, 50.0, 1.0) = 0.0;
uniform float vortex_morph : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec2 vortex_shift = vec2(0.0, 0.0);
uniform float vortex_phase : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float vortex_aperture : hint_range(0.0, 1.0, 0.01) = 0.5;


// --- CIRCLE INVERSION ---
uniform float inversion_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float inversion_radius   : hint_range(0.1, 2.0, 0.01) = 0.5;
uniform float inversion_zoom     : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float inversion_speed    : hint_range(-2.0, 2.0, 0.01) = 0.0;


// --- SPIRAL TILE ---
uniform float spiral_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float spiral_zoom     : hint_range(0.1, 4.0, 0.01) = 1.5;
uniform float spiral_twist    : hint_range(-3.14159, 3.14159, 0.01) = 0.5;
uniform float spiral_speed    : hint_range(-2.0, 2.0, 0.01) = 0.0;

// --- PIXELATE ---
uniform float pixelate : hint_range(0.0, 1.0, 0.005) = 0.0;

// --- QUATERNION TUMBLE ---
uniform vec4 q_rot = vec4(0.0, 0.0, 0.0, 1.0);
uniform float tumble_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glitch_factor : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glitch_style : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float glitch_speed : hint_range(0.1, 60.0, 0.1) = 1.0;

// --- RGB SPLIT ---
uniform float rgb_split : hint_range(0.0, 0.1, 0.001) = 0.0;
uniform float rgb_split_speed : hint_range(0.0, 5.0, 0.01) = 1.0;

// --- HUE SHIFT ---
uniform float hue_cycle_rate : hint_range(0.0, 5.0, 0.01) = 0.0;
uniform float hue_shift_range : hint_range(0.0, 1.0, 0.01) = 1.0;

// --- PLASMA ---
uniform float plasma_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float plasma_rings : hint_range(1.0, 20.0, 1.0) = 5.0;
uniform float plasma_speed : hint_range(0.0, 5.0, 0.01) = 1.0;

// --- THERMAL ---
uniform float thermal_shift : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float thermal_speed : hint_range(0.0, 5.0, 0.01) = 0.0;

// --- RADIAL REPEAT ---
uniform float radial_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float radial_sides    : hint_range(2.0, 16.0, 1.0) = 6.0;
uniform float radial_offset   : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float radial_zoom     : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float radial_speed    : hint_range(-2.0, 2.0, 0.01) = 0.0;


// --- INVERT ---
uniform float invert : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- RAINBOW PULSE ---
uniform float rainbow_pulse : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float rainbow_speed : hint_range(0.0, 5.0, 0.01) = 1.0;

// --- TV STATIC & SCAN LINES ---
uniform float tv_static : hint_range(0.0, 3.0, 0.01) = 0.0;
uniform float static_speed : hint_range(1.0, 60.0, 1.0) = 24.0;
uniform float scanline_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float scanline_count : hint_range(60.0, 1080.0, 60.0) = 240.0;
uniform float scanline_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;
uniform float digital_lines : hint_range(0.0, 1.0, 0.01) = 0.0;


// --- RAY MARCH / VOLUMETRIC GLOW ---
uniform float ray_intensity : hint_range(0.0, 2.0, 0.01) = 0.0;
uniform float ray_angle : hint_range(0.0, 6.28, 0.01) = 0.0;
uniform float max_steps : hint_range(2.0, 150.0, 1.0) = 64.0;
uniform float step_length : hint_range(0.001, 0.03, 0.001) = 0.01;
uniform float ray_spread : hint_range(0.1, 10.0, 0.01) = 2.0;
uniform float ray_softness : hint_range(1.0, 10.0, 0.01) = 3.0;
uniform vec4 ray_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float ray_rainbow_mix : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float ray_cycle_speed : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float ray_pulse_freq : hint_range(0.0, 10.0, 0.01) = 0.0;
uniform float feedback_amount : hint_range(0.0, 0.5, 0.01) = 0.0;
uniform float feedback_drift : hint_range(-0.05, 0.05, 0.001) = 0.0;
uniform float ray_spin_speed  : hint_range(-2.0, 2.0, 0.01) = 0.0;
uniform float ray_pulse_amount : hint_range(0.0, 3.14159, 0.01) = 0.0;
uniform float ray_pulse_speed  : hint_range(0.0, 5.0, 0.01) = 1.0;

// --- ROTATIONAL SYMMETRY ---
uniform float rot_sym_sides : hint_range(2.0, 16.0, 1.0) = 2.0;
uniform float rot_sym_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float rot_sym_offset : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float rot_sym_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;
uniform float rot_sym_zoom : hint_range(0.1, 4.0, 0.01) = 1.0;





// --- MIRROR TILE ---
uniform float mirror_divisions : hint_range(1.0, 8.0, 1.0) = 1.0;
uniform float mirror_strength  : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float mirror_zoom      : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float mirror_rotation  : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float mirror_rot_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;

// Mobius spiral
uniform float mobius_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float mobius_speed    : hint_range(-2.0, 2.0, 0.01) = 0.5;
uniform float mobius_zoom     : hint_range(0.1, 3.0, 0.01) = 1.0;
uniform float mobius_twist    : hint_range(-3.14159, 3.14159, 0.01) = 0.0;
uniform float mobius_center : hint_range(0.1, 0.9, 0.01) = 0.5;



// --- MASK ---
uniform float mask_radius : hint_range(0.01, 1.0, 0.01) = 1.0;
uniform float mask_stretch : hint_range(-6.1, 6.1, 0.01) = 1.0;

// --- COLOR GRADE ---
uniform float grade_shadows : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float grade_midtones : hint_range(0.1, 3.0, 0.01) = 1.0;
uniform float grade_highlights : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform vec4 grade_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// --- EDGE GLOW ---
uniform float edge_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_thickness : hint_range(0.5, 5.0, 0.1) = 1.0;
uniform vec4 edge_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform float edge_pulse_speed : hint_range(0.0, 5.0, 0.01) = 0.0;

// --- BLUR / BLOOM ---
uniform float blur_amount : hint_range(0.0, 0.02, 0.001) = 0.0;
uniform float bloom_strength : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- BASE ADJUSTMENTS ---
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float brightness : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float contrast : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;

// --- AURA / ENERGY FIELD ---
uniform float aura_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float aura_speed : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float aura_frequency : hint_range(1.0, 20.0, 0.1) = 8.0;
uniform float aura_radius : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform vec4 aura_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);

// --- REALITY TEARING / POLAR WARP ---
uniform float rift_feather : hint_range(0.01, 0.5, 0.01) = 0.1;
uniform float polar_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float polar_rotation : hint_range(0.0, 6.28318, 0.01) = 0.0;
uniform float polar_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;
uniform float polar_zoom : hint_range(0.1, 3.0, 0.01) = 1.0;

// -- Voronoi
uniform float voronoi_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float voronoi_scale    : hint_range(1.0, 20.0, 0.1) = 5.0;
uniform float voronoi_speed    : hint_range(-2.0, 2.0, 0.01) = 0.5;
uniform float voronoi_border   : hint_range(0.0, 1.0, 0.01) = 0.3;
// Julia Set
uniform float julia_strength  : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float julia_cx        : hint_range(-2.0, 2.0, 0.001) = -0.7;
uniform float julia_cy        : hint_range(-2.0, 2.0, 0.001) = 0.27;
uniform float julia_zoom      : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float julia_speed     : hint_range(-2.0, 2.0, 0.01) = 0.3;
uniform int   julia_iterations: hint_range(4, 32, 1) = 16;
// Droste
uniform float droste_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float droste_speed    : hint_range(-2.0, 2.0, 0.01) = 0.3;
uniform float droste_zoom     : hint_range(0.5, 4.0, 0.01) = 1.5;
uniform float droste_twist    : hint_range(-3.14159, 3.14159, 0.01) = 0.5;

// Newtonian Fractal
uniform float newton_strength   : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float newton_zoom       : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float newton_speed      : hint_range(-2.0, 2.0, 0.01) = 0.2;
uniform float newton_color_mix  : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform int   newton_iterations : hint_range(2, 16, 1) = 8;

// =============================================================================
// HELPERS
// =============================================================================

// Complex multiply
vec2 cmul(vec2 a, vec2 b) {
    return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

// Complex divide
vec2 cdiv(vec2 a, vec2 b) {
    float d = dot(b, b);
    return vec2(dot(a, b), a.y*b.x - a.x*b.y) / d;
}

// Newton fractal iteration for f(z) = z^3 - 1
// Roots are at 1, (-1+i*sqrt(3))/2, (-1-i*sqrt(3))/2
vec3 newton_iterate(vec2 z, int max_iter) {
    vec2 root1 = vec2(1.0, 0.0);
    vec2 root2 = vec2(-0.5,  0.866025);
    vec2 root3 = vec2(-0.5, -0.866025);
    
    for (int i = 0; i < max_iter; i++) {
        // f(z) = z^3 - 1
        vec2 z2  = cmul(z, z);
        vec2 z3  = cmul(z2, z);
        vec2 fz  = z3 - vec2(1.0, 0.0);
        // f'(z) = 3z^2
        vec2 dfz = 3.0 * z2;
        // Newton step: z = z - f(z)/f'(z)
        z = z - cdiv(fz, dfz);
    }
    
    // Determine which root we converged to
    float d1 = length(z - root1);
    float d2 = length(z - root2);
    float d3 = length(z - root3);
    
    if (d1 < d2 && d1 < d3) return vec3(1.0, 0.0, 0.0); // red   → root 1
    if (d2 < d1 && d2 < d3) return vec3(0.0, 1.0, 0.0); // green → root 2
    return vec3(0.0, 0.0, 1.0);                           // blue  → root 3
}

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float sync_speed(float speed) {
	return mix(speed, floor(speed + 0.5), sync_to_loop);
}

vec2 rotate_uv(vec2 uv, float angle) {
	float s = sin(angle); float c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c)) * uv;
}

// Simple box blur sample — samples 8 neighbours
vec4 box_blur(sampler2D tex, vec2 uv, float radius) {
	vec4 col = vec4(0.0);
	col += texture(tex, fract(uv + vec2(-radius, -radius)));
	col += texture(tex, fract(uv + vec2(0.0,    -radius)));
	col += texture(tex, fract(uv + vec2( radius, -radius)));
	col += texture(tex, fract(uv + vec2(-radius,  0.0)));
	col += texture(tex, fract(uv));
	col += texture(tex, fract(uv + vec2( radius,  0.0)));
	col += texture(tex, fract(uv + vec2(-radius,  radius)));
	col += texture(tex, fract(uv + vec2(0.0,     radius)));
	col += texture(tex, fract(uv + vec2( radius,  radius)));
	return col / 9.0;
}

// Sobel edge detection — returns edge intensity 0.0-1.0
float sobel_edge(sampler2D tex, vec2 uv, float thickness) {
	float px = thickness / 512.0;
	float tl = length(texture(tex, fract(uv + vec2(-px, -px))).rgb);
	float t  = length(texture(tex, fract(uv + vec2(0.0, -px))).rgb);
	float tr = length(texture(tex, fract(uv + vec2( px, -px))).rgb);
	float l  = length(texture(tex, fract(uv + vec2(-px,  0.0))).rgb);
	float r  = length(texture(tex, fract(uv + vec2( px,  0.0))).rgb);
	float bl = length(texture(tex, fract(uv + vec2(-px,  px))).rgb);
	float b  = length(texture(tex, fract(uv + vec2(0.0,  px))).rgb);
	float br = length(texture(tex, fract(uv + vec2( px,  px))).rgb);
	float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
	float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
	return clamp(sqrt(gx*gx + gy*gy), 0.0, 1.0);
}
// voronoi helpers
vec2 voronoi_hash(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

float voronoi(vec2 uv, float time) {
    vec2 p = floor(uv);
    vec2 f = fract(uv);
    float min_dist = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 neighbor = vec2(float(i), float(j));
            vec2 point = voronoi_hash(p + neighbor);
            point = 0.5 + 0.5 * sin(time + PI * 2.0 * point);
            vec2 diff = neighbor + point - f;
            min_dist = min(min_dist, length(diff));
        }
    }
    return min_dist;
}

// =============================================================================
// FRAGMENT
// =============================================================================

void fragment() {
	// -------------------------------------------------------------------------
	// 1. CENTER UVs
	// -------------------------------------------------------------------------
	vec2 uv = UV - 0.5;

	// -------------------------------------------------------------------------
	// 2. PRE-KALEIDOSCOPE ROTATION
	// Animates the kaleidoscope pattern when combined with kaleido_sides
	// -------------------------------------------------------------------------
	if (abs(pre_rotation_angle) > 0.001 || abs(pre_rotation_speed) > 0.001) {
		float spd   = sync_speed(pre_rotation_speed);
		float angle = pre_rotation_angle + manual_time * PI * 2.0 * spd;
		uv = rotate_uv(uv, angle);
	}

	// -------------------------------------------------------------------------
	// 3. ZOOM
	// -------------------------------------------------------------------------
	uv *= fold_zoom;

	// =========================================================================
	// GEOMETRIC DISTORTIONS
	// =========================================================================

	// --- KALEIDOSCOPE ---
	if (kaleido_sides > 1.5) {
		float a     = atan(uv.y, uv.x);
		float r     = length(uv);
		float slice = PI * 2.0 / kaleido_sides;
		a = mod(a, slice);
		a = abs(a - slice * 0.5);
		uv = vec2(cos(a), sin(a)) * r;
	}
	
	// --- ROTATIONAL SYMMETRY ---
if (rot_sym_strength > 0.001) {
    float spd    = sync_speed(rot_sym_speed);
    float offset = rot_sym_offset + manual_time * PI * 2.0 * spd;

    float r = length(uv) * rot_sym_zoom;
    float a = atan(uv.y, uv.x) + offset;

    // Snap angle to nearest sector
    float slice = PI * 2.0 / rot_sym_sides;
    a = mod(a, slice);

    vec2 sym_uv = vec2(cos(a), sin(a)) * r;
    uv = mix(uv, sym_uv, rot_sym_strength);
}





	// --- POST ROTATION (whole image after kaleidoscope) ---
	if (abs(u_rotation) > 0.001 || abs(post_rotation_speed) > 0.001) {
		float spd   = sync_speed(post_rotation_speed);
		float angle = u_rotation + manual_time * PI * 2.0 * spd;
		uv = rotate_uv(uv, angle);
	}

	// --- GEOMETRIC FOLD ---
	if (fold_number > 0.5) {
		for (int i = 0; i < 8; i++) {
			if (float(i) >= fold_number) break;
			uv = abs(uv);
			if (abs(fold_rot_speed) > 0.001) {
				float spd = sync_speed(fold_rot_speed);
				uv = rotate_uv(uv, manual_time * PI * 2.0 * spd);
			}
			uv -= 0.3;
		}
	}

	// --- HEX TILE ---
	if (hex_scale > 1.5) {
		vec2 hex_uv = uv * hex_scale;
		vec2 r_hex  = vec2(1.0, 1.73205);
		vec2 h_hex  = r_hex * 0.5;
		vec2 a_hex  = mod(hex_uv, r_hex) - h_hex;
		vec2 b_hex  = mod(hex_uv - h_hex, r_hex) - h_hex;
		vec2 g_uv   = dot(a_hex, a_hex) < dot(b_hex, b_hex) ? a_hex : b_hex;
		if (abs(hex_rot_speed) > 0.001) {
			float spd = sync_speed(hex_rot_speed);
			g_uv = rotate_uv(g_uv, manual_time * PI * 2.0 * spd);
		}
		uv = g_uv / hex_scale;
	}

	// --- MIRROR TILE ---
	if (mirror_strength > 0.001) {
		float spd = sync_speed(mirror_rot_speed);
		float angle = mirror_rotation + manual_time * PI * 2.0 * spd;
		if (abs(angle) > 0.001) {
			uv = rotate_uv(uv, angle);
		}

		// Scale into tile space
		vec2 tile_uv = uv * mirror_divisions * mirror_zoom;

		// Mirror each axis: even cells are flipped, odd cells are not
		vec2 cell = floor(tile_uv);
		vec2 local = fract(tile_uv);
		if (mod(cell.x, 2.0) >= 1.0) local.x = 1.0 - local.x;
		if (mod(cell.y, 2.0) >= 1.0) local.y = 1.0 - local.y;

		// Remap back to centered UV space
		vec2 mirrored_uv = (local - 0.5) / (mirror_divisions * mirror_zoom);
		uv = mix(uv, mirrored_uv, mirror_strength);
	}

	// =========================================================================
	// UV WARP DISTORTIONS
	// =========================================================================

	// --- MOBIUS SPIRAL ---
if (mobius_strength > 0.001) {
    float spd = sync_speed(mobius_speed);
    float t   = manual_time * PI * 2.0 * spd + mobius_twist;
    
    vec2 z = (uv - 0.5) * 2.0 * mobius_zoom;
    
    // adjustable centerpoint
    vec2 a = vec2(mobius_center, 0.0);
    
    // Rotate z instead of a — creates spinning spiral in place
    float ca = cos(t);
    float sa = sin(t);
    z = vec2(z.x * ca - z.y * sa, z.x * sa + z.y * ca);
    
    vec2 z_minus_a = z - a;
    vec2 conj_a    = vec2(a.x, -a.y);
    vec2 denom     = vec2(1.0, 0.0) - vec2(
        conj_a.x * z.x - conj_a.y * z.y,
        conj_a.x * z.y + conj_a.y * z.x
    );
    
    float denom_sq = dot(denom, denom);
    if (denom_sq > 0.0001) {
        vec2 mobius_z = vec2(
            z_minus_a.x * denom.x + z_minus_a.y * denom.y,
            z_minus_a.y * denom.x - z_minus_a.x * denom.y
        ) / denom_sq;
        
        vec2 mobius_uv = mobius_z * 0.5 + 0.5;
        uv = mix(uv, mobius_uv, mobius_strength);
    }
}






	// --- FISHEYE ---
	if (abs(fisheye) > 0.01) {
		float r = length(uv);
		uv = uv * (1.0 + r * r * fisheye);
	}

	// --- WAVE ---
	if (wave_amplitude > 0.001) {
		float spd  = sync_speed(wave_speed);
		float freq = mix(wave_frequency, floor(wave_frequency + 0.5), sync_to_loop);
		uv.x += sin(uv.y * freq + manual_time * PI * 2.0 * spd) * (wave_amplitude * 0.05);
	}

	// --- RIPPLE ---
	if (ripple_strength > 0.001) {
		float r    = length(uv);
		float spd  = sync_speed(ripple_speed);
		float freq = mix(ripple_frequency, floor(ripple_frequency + 0.5), sync_to_loop);
		if (r > 0.001) {
			uv += normalize(uv) * sin(r * freq * PI * 2.0 - manual_time * PI * 2.0 * spd)
				  * ripple_strength * 0.1;
		}
	}

	// --- SWIRL ---
	if (swirl_strength != 0.00) {
		float dist  = length(uv);
		float spd   = sync_speed(swirl_speed);
		float angle = (swirl_strength * dist) + (manual_time * PI * 2.0 * spd);
		uv = rotate_uv(uv, angle);
	}

	// --- POINCARE WARP ---
	if (poincare_warp > 0.01) {
		float r        = length(uv);
		float strength = clamp(poincare_warp * 1.5, 0.0, 0.99);
		float warp     = 1.0 / max(0.001, 1.0 - (pow(r, 1.5) * strength));
		uv *= warp;
	}

	// --- HYPERBOLIC BEND ---
	if (hyperbolic_bend > 0.001) {
		float r        = length(uv);
		float inversion = (hyperbolic_bend * 0.1) / (r * r + 0.01);
		uv *= inversion;
	}

	// --- VORTEX LATTICE ---
	if (vortex_density > 0.1) {
		float v_alpha  = clamp(vortex_density * 0.02, 0.0, 1.0);
		float v_time   = manual_time + vortex_phase * 0.05;
		vec2  v_uv     = (uv + vortex_shift) * vortex_density;
		float bend     = vortex_morph * 0.1;
		v_uv.x += cos(v_uv.y * 0.8 + v_time) * bend;
		v_uv.y += sin(v_uv.x * 0.8 + v_time) * bend;
		float v_dist    = length(fract(v_uv) - 0.5);
		float norm_ap   = vortex_aperture * 0.5;
		float v_mask    = smoothstep(norm_ap, norm_ap - 0.1, v_dist);
		uv *= mix(1.0, 1.0 + v_mask, 0.3 * v_alpha);
	}

	// --- PIXELATE ---
	if (pixelate > 0.001) {
		vec2  size = vec2(textureSize(TEXTURE, 0));
		float f    = mix(1.0, 0.02, pixelate);
		uv = floor(uv * size * f) / (size * f);
	}

	// --- POLAR WARP / REALITY RIFT ---
	if (polar_strength > 0.001) {
	    float spd = sync_speed(polar_speed);
	    float angle = atan(uv.y, uv.x) + manual_time * PI * 2.0 * spd + polar_rotation;
	    float r = length(uv);
	    
	    // Number of tear seams based on polar_zoom
	    float seams = floor(polar_zoom);
	    
	    // Create the rift displacement at each seam
	    float sector = floor(angle / (PI * 2.0 / seams));
	    float seam_proximity = fract(angle / (PI * 2.0 / seams));
		float tear = smoothstep(0.0, rift_feather, seam_proximity) 
           * smoothstep(1.0, 1.0 - rift_feather, seam_proximity);
	    
	    // Displace UV across the tear
	    vec2 rift_offset = vec2(
	        sin(sector + manual_time * spd) * r,
	        cos(sector + manual_time * spd) * r
	    ) * (1.0 - tear) * polar_strength * 0.3;
	    
	    uv = mix(uv, uv + rift_offset, polar_strength);
	}



	// --- QUATERNION TUMBLE ---
	if (tumble_strength > 0.01) {
		float safe_time     = mod(manual_time, 10.0);
		float digital_steps = floor(safe_time * glitch_speed) / glitch_speed;
		float morphed_time  = mix(safe_time, digital_steps, glitch_style);
		vec3  p             = vec3(uv, sqrt(max(0.0, 1.0 - dot(uv, uv))));
		float noise         = rand(vec2(digital_steps)) * glitch_style;
		vec4  q_jitter      = q_rot + (sin(morphed_time * 4.0) + noise) * glitch_factor;
		vec4  q             = normalize(mix(q_rot, q_jitter, glitch_factor));
		vec3  q_xyz         = q.xyz;
		float q_w           = q.w;
		vec3  temp          = cross(q_xyz, p) + q_w * p;
		vec3  p_rot         = p + 2.0 * cross(q_xyz, temp);
		uv = mix(uv, p_rot.xy, tumble_strength);
	}

// --- CIRCLE INVERSION ---
if (inversion_strength > 0.001) {
    float spd = sync_speed(inversion_speed);
    float angle = manual_time * PI * 2.0 * spd;

    // Optionally rotate before inverting for a spinning effect
    vec2 inv_uv = abs(angle) > 0.001 ? rotate_uv(uv, angle) : uv;
    inv_uv *= inversion_zoom;

    float r2 = dot(inv_uv, inv_uv);
    // Invert through a circle of given radius: uv -> radius^2 / |uv|^2 * uv
    float inv_radius2 = inversion_radius * inversion_radius;
    vec2 inverted = (r2 > 0.0001) ? inv_uv * (inv_radius2 / r2) : inv_uv;

    uv = mix(uv, inverted, inversion_strength);
}

// --- SPIRAL TILE ---
if (spiral_strength > 0.001) {
    float spd = sync_speed(spiral_speed);
    float t   = manual_time * spd;

    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Map to log-polar space
    vec2 log_polar = vec2(log(max(r, 0.0001)), a);

    // Scroll log-radius over time for the infinite zoom
    log_polar.x += t;

    // Twist — shears the angle relative to the radius
    log_polar.y += log_polar.x * spiral_twist;

    // Tile log-polar space
    log_polar.x  = fract(log_polar.x / spiral_zoom) * spiral_zoom;

    // Map back to cartesian
    float exp_r  = exp(log_polar.x);
    vec2 spiral_uv = vec2(
        exp_r * cos(log_polar.y),
        exp_r * sin(log_polar.y)
    );

    uv = mix(uv, spiral_uv, spiral_strength);
}

// --- RADIAL REPEAT ---
if (radial_strength > 0.001) {
    float spd    = sync_speed(radial_speed);
    float offset = radial_offset + manual_time * PI * 2.0 * spd;

    vec2  r_uv   = uv * radial_zoom;
    float r      = length(r_uv);
    float a      = atan(r_uv.y, r_uv.x) + offset;

    // Snap to sector — no mirror, just repeat
    float slice  = PI * 2.0 / radial_sides;
    a            = mod(a, slice);

    // Rotate offset back out so the stamp sits correctly
    a           -= offset;

    vec2 radial_uv = vec2(cos(a), sin(a)) * r / radial_zoom;
    uv = mix(uv, radial_uv, radial_strength);
}

// --- PINWHEEL ---
if (pinwheel_strength > 0.001) {
    float spd  = sync_speed(pinwheel_speed);
    float t    = manual_time * PI * 2.0 * spd;

    vec2  p_uv = uv * pinwheel_zoom;
    float r    = length(p_uv);
    float a    = atan(p_uv.y, p_uv.x) + t;

    // Which sector are we in
    float slice  = PI * 2.0 / pinwheel_sides;
    float sector = floor(a / slice);
    float local_a = mod(a, slice);

    // Apply progressive twist per sector — this is what makes it a pinwheel
    float blade_rotation = sector * pinwheel_twist;
    local_a += blade_rotation;

    vec2 pinwheel_uv = vec2(cos(local_a), sin(local_a)) * r / pinwheel_zoom;
    uv = mix(uv, pinwheel_uv, pinwheel_strength);
}

	// =========================================================================
	// WRAP
	// =========================================================================
	vec2 wrapped_uv = fract(uv + 0.5);
	
	
	
	

	// =========================================================================
	// TEXTURE SAMPLING
	// =========================================================================

	vec4 tex;
	if (rgb_split > 0.001) {
		float spd    = sync_speed(rgb_split_speed);
		float offset = rgb_split * sin(manual_time * PI * 2.0 * spd);
		float r_ch   = texture(TEXTURE, wrapped_uv + vec2(offset, 0.0)).r;
		float g_ch   = texture(TEXTURE, wrapped_uv).g;
		float b_ch   = texture(TEXTURE, wrapped_uv - vec2(offset, 0.0)).b;
		tex = vec4(r_ch, g_ch, b_ch, texture(TEXTURE, wrapped_uv).a);
	} else if (blur_amount > 0.001) {
		tex = box_blur(TEXTURE, wrapped_uv, blur_amount);
	} else {
		tex = texture(TEXTURE, wrapped_uv);
	}

	tex.rgb *= base_color.rgb;



	// =========================================================================
	// POST PROCESS EFFECTS
	// =========================================================================




	// --- BLOOM ---
	if (bloom_strength > 0.001 && blur_amount > 0.001) {
		vec4 blurred = box_blur(TEXTURE, wrapped_uv, blur_amount * 2.0);
		tex.rgb += blurred.rgb * bloom_strength;
	}

	// --- VOLUMETRIC GLOW (RAY MARCH) ---
		if (ray_intensity > 0.01) {
    // Animate the ray angle
    float spd         = sync_speed(ray_spin_speed);
    float pulse_spd   = sync_speed(ray_pulse_speed);
    float live_angle  = ray_angle
        + manual_time * PI * 2.0 * spd
        + sin(manual_time * PI * 2.0 * pulse_spd) * ray_pulse_amount;

    vec2  current_pos   = wrapped_uv;
		float hit_dist      = -1.0;
		float accum_density = 0.0;

		for (int i = 0; i < int(max_steps); i++) {
			float d_center = length(current_pos - 0.5);
			float spiral   = live_angle + (d_center * hyperbolic_bend * 2.0);
			vec2  bent_dir = vec2(cos(spiral), sin(spiral));
			current_pos   += bent_dir * (step_length * (1.0 - hit_dist * 0.5));
			float sample_a  = texture(TEXTURE, fract(current_pos)).a;
			if (sample_a > 0.1) {
				accum_density += (1.0 - accum_density) * (sample_a * 0.2);
				if (hit_dist < 0.0) hit_dist = float(i) / max_steps;
			}
			if (accum_density > 0.95) break;
		}

		if (hit_dist > -1.0) {
			float pulse_val = 1.0;
			if (ray_pulse_freq > 0.01) {
				float pf    = sync_speed(ray_pulse_freq);
				pulse_val   = sin(manual_time * PI * 2.0 * pf) * 0.5 + 0.5;
			}
			float falloff       = pow(1.0 - hit_dist, ray_softness);
			float final_intensity = falloff * ray_intensity * ray_spread * pulse_val * accum_density;
			float cs    = sync_speed(ray_cycle_speed);
			float phase = (manual_time * PI * 2.0 * cs) + (hit_dist * 5.0);
			vec3 rainbow = vec3(
				sin(phase) * 0.5 + 0.5,
				sin(phase + 2.094) * 0.5 + 0.5,
				sin(phase + 4.189) * 0.5 + 0.5
			);
			vec3 glow_color = mix(ray_color.rgb, rainbow, ray_rainbow_mix);

			if (feedback_amount > 0.01) {
				vec3  fb_accum = vec3(0.0);
				float fa_accum = 0.0;
				for (int fi = 1; fi <= 4; fi++) {
					float offset   = float(fi) * 0.01 * feedback_amount;
					vec2  drift    = vec2(
						sin(manual_time * PI * 2.0 + offset),
						cos(manual_time * PI * 2.0 + offset)
					) * offset;
					vec2  ghost_uv = fract(wrapped_uv + (feedback_drift * float(fi)) + drift);
					vec4  ghost    = texture(TEXTURE, ghost_uv);
					float fade     = pow(feedback_amount, float(fi));
					fb_accum      += ghost.rgb * fade;
					fa_accum      += ghost.a   * fade;
				}
				tex.rgb = mix(tex.rgb, tex.rgb + fb_accum, feedback_amount);
				tex.a   = max(tex.a, fa_accum * feedback_amount);
			}

			tex.rgb += glow_color * final_intensity;
			tex.a    = clamp(tex.a + (final_intensity * 0.5), 0.0, 1.0);
		}
	}


	// --- PLASMA ---
	if (plasma_strength > 0.001) {
		float dist  = length(UV - 0.5);
		float spd   = sync_speed(plasma_speed);
		float rings = mix(plasma_rings, floor(plasma_rings + 0.5), sync_to_loop);
		float v     = sin(dist * (PI * 2.0 * rings) - manual_time * PI * 2.0 * spd);
		vec3 plasma_col;
		plasma_col.r = sin(v * 2.0 + manual_time * PI * 2.0) * 0.5 + 0.5;
		plasma_col.g = sin(v * 2.0 + 2.094 + manual_time * PI * 2.0) * 0.5 + 0.5;
		plasma_col.b = sin(v * 2.0 + 4.189 + manual_time * PI * 2.0) * 0.5 + 0.5;
		tex.rgb = mix(tex.rgb, plasma_col, plasma_strength);
	}

	// --- THERMAL ---
	if (thermal_shift > 0.001) {
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		float spd = sync_speed(thermal_speed);
		float t   = lum * 10.0 + manual_time * PI * 2.0 * spd;
		vec3  thermal = vec3(lum, 1.0 - lum, sin(t));
		tex.rgb = mix(tex.rgb, thermal, thermal_shift);
	}

	// --- HUE SHIFT ---
	if (hue_cycle_rate > 0.001) {
		const mat3 rgb2yiq = mat3(
			vec3(0.299,  0.587,  0.114),
			vec3(0.596, -0.274, -0.322),
			vec3(0.211, -0.523,  0.312)
		);
		const mat3 yiq2rgb = mat3(
			vec3(1.0,  0.956,  0.621),
			vec3(1.0, -0.272, -0.647),
			vec3(1.0, -1.106,  1.703)
		);
		vec3  yiq  = rgb2yiq * tex.rgb;
		float spd  = sync_speed(hue_cycle_rate);
		float hue  = manual_time * PI * 2.0 * spd * hue_shift_range;
		float ch   = cos(hue); float sh = sin(hue);
		vec2  rotated_chroma = vec2(
			yiq.y * ch - yiq.z * sh,
			yiq.y * sh + yiq.z * ch
		);
		tex.rgb = yiq2rgb * vec3(yiq.x, rotated_chroma.x, rotated_chroma.y);
	}

	// --- INVERT ---
	if (invert > 0.001) {
		tex.rgb = mix(tex.rgb, 1.0 - tex.rgb, invert);
	}

	// --- BRIGHTNESS / CONTRAST / SATURATION ---
	tex.rgb  = (tex.rgb - 0.5) * contrast + 0.5 + brightness;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	tex.rgb  = mix(vec3(lum), tex.rgb, saturation);

	// --- COLOR GRADE ---
	if (grade_shadows != 0.0 || grade_midtones != 1.0 || grade_highlights != 1.0) {
		// Lift shadows
		tex.rgb += grade_shadows * (1.0 - tex.rgb);
		// Gamma midtones
		tex.rgb  = pow(max(tex.rgb, vec3(0.0)), vec3(1.0 / max(grade_midtones, 0.01)));
		// Gain highlights
		tex.rgb *= grade_highlights;
		// Tint
		tex.rgb *= grade_tint.rgb;
	}

	// --- EDGE GLOW ---
	if (edge_strength > 0.001) {
		float pulse = 1.0;
		if (edge_pulse_speed > 0.001) {
			float spd = sync_speed(edge_pulse_speed);
			pulse = sin(manual_time * PI * 2.0 * spd) * 0.5 + 0.5;
		}
		float edge = sobel_edge(TEXTURE, wrapped_uv, edge_thickness);
		tex.rgb = mix(tex.rgb, edge_color.rgb, edge * edge_strength * pulse);
	}
	
		// --- AURA / ENERGY FIELD ---
	if (aura_strength > 0.001) {
	    // 1. Sample luminance of nearby pixels to find bright areas
	    float lum_center = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	    
	    // 2. Create organic pulsing displacement field
	    float spd = sync_speed(aura_speed);
	    float freq = aura_frequency;
	    float t = manual_time * PI * 2.0 * spd;
	    
	    // Layered sine waves create organic movement
	    vec2 aura_offset;
	    aura_offset.x = sin(wrapped_uv.y * freq + t) * 0.003
	                  + sin(wrapped_uv.y * freq * 0.7 + t * 1.3) * 0.002
	                  + sin(wrapped_uv.y * freq * 1.4 + t * 0.8) * 0.001;
	    aura_offset.y = cos(wrapped_uv.x * freq + t * 0.9) * 0.003
	                  + cos(wrapped_uv.x * freq * 0.8 + t * 1.1) * 0.002
	                  + cos(wrapped_uv.x * freq * 1.3 + t * 0.7) * 0.001;
	    
	    // 3. Scale displacement by luminance — bright areas radiate more
	    aura_offset *= lum_center * aura_strength * 10.0;
	    
	    // 4. Sample displaced position
	    vec4 aura_sample = texture(TEXTURE, fract(wrapped_uv + aura_offset));
	    
	    // 5. Create glow mask — falls off from bright areas
	    float dist_from_center = length(wrapped_uv - 0.5);
	    float aura_mask = smoothstep(aura_radius + 0.3, aura_radius, dist_from_center);
	    aura_mask *= lum_center;
	    
	    // 6. Blend aura color over displaced sample
	    vec3 aura_glow = mix(aura_sample.rgb, aura_color.rgb, 
	                         aura_strength * 0.3 * aura_mask);
	    
	    // 7. Add pulsing outer glow
	    float pulse = sin(t + dist_from_center * freq) * 0.5 + 0.5;
	    aura_glow += aura_color.rgb * pulse * aura_strength * aura_mask * 0.4;
	    
	    tex.rgb = mix(tex.rgb, aura_glow, aura_strength * aura_mask);
	    
	    // 8. Add subtle overall shimmer on bright pixels
	    float shimmer = sin(wrapped_uv.x * freq * 3.0 + t) 
	                  * cos(wrapped_uv.y * freq * 2.0 + t * 1.2) * 0.5 + 0.5;
	    tex.rgb += aura_color.rgb * shimmer * lum_center 
	             * aura_strength * 0.15 * aura_mask;
	}

	// --- TV STATIC ---
	if (tv_static > 0.001) {
		float spd   = floor(manual_time * static_speed);
		float noise = rand(wrapped_uv + vec2(spd));
		tex.rgb    += (noise - 0.5) * tv_static;
	}

	// --- SCAN LINES ---
	if (scanline_strength > 0.001) {
		float spd      = sync_speed(scanline_speed);
		float scroll   = manual_time * spd;
		float line     = sin((wrapped_uv.y + scroll) * scanline_count * PI) * 0.5 + 0.5;
		float scanline = pow(line, 2.0);
		tex.rgb = mix(tex.rgb, tex.rgb * scanline, scanline_strength);
	}

	// --- DIGITAL LINES ---
	if (digital_lines > 0.001) {
		float line_seed = floor(wrapped_uv.x * 64.0) + floor(manual_time * 12.0);
		float glitch    = step(0.97, rand(vec2(line_seed, 0.0)));
		float offset    = (rand(vec2(line_seed, 1.0)) - 0.5) * 0.1;
		vec2  glitch_uv = vec2(fract(wrapped_uv.x + offset * glitch), wrapped_uv.y);
		vec4  glitch_col = texture(TEXTURE, glitch_uv);
		tex.rgb = mix(tex.rgb, glitch_col.rgb, glitch * digital_lines);
	}

	// --- RAINBOW PULSE ---
	if (rainbow_pulse > 0.001) {
		float spd = sync_speed(rainbow_speed);
		vec3  rainbow;
		rainbow.r = cos(manual_time * PI * 2.0 * spd) * 0.5 + 0.5;
		rainbow.g = cos(manual_time * PI * 2.0 * spd + 2.094) * 0.5 + 0.5;
		rainbow.b = cos(manual_time * PI * 2.0 * spd + 4.189) * 0.5 + 0.5;
		float glow = sin(manual_time * PI * 2.0 * spd) * 0.5 + 0.5;
		tex.rgb = mix(tex.rgb, rainbow, rainbow_pulse * glow);
	}
	// --- DROSTE EFFECT ---
if (droste_strength > 0.001) {
    float spd = sync_speed(droste_speed);
    float t   = manual_time * spd;
    
    // Map to complex log space
    vec2 z = uv - 0.5;
    float r = length(z);
    float a = atan(z.y, z.x);
    
    // Complex logarithm
    vec2 log_z = vec2(log(r), a);
    
    // Add time-based scroll for animation + twist
    log_z.x += t;
    log_z.y += droste_twist;
    
    // Scale for zoom
    log_z *= droste_zoom;
    
    // Map back to UV space via complex exponential
    float exp_x = exp(log_z.x);
    vec2 droste_uv = vec2(
        exp_x * cos(log_z.y),
        exp_x * sin(log_z.y)
    ) * 0.5 + 0.5;
    
    vec4 droste_tex = texture(TEXTURE, fract(droste_uv));
    tex.rgb = mix(tex.rgb, droste_tex.rgb, droste_strength * smoothstep(0.0, 0.3, r));}

// voronoi
    if (voronoi_strength > 0.001) {
        float spd   = sync_speed(voronoi_speed);
        float t     = manual_time * PI * 2.0 * spd;
        vec2 vor_uv = wrapped_uv * voronoi_scale;

        // Sample voronoi at 4 neighbours to build a gradient direction
        float eps = 0.05;
        float v_c  = voronoi(vor_uv, t);
        float v_r  = voronoi(vor_uv + vec2(eps,  0.0), t);
        float v_u  = voronoi(vor_uv + vec2(0.0,  eps), t);
        float v_l  = voronoi(vor_uv + vec2(-eps, 0.0), t);
        float v_d  = voronoi(vor_uv + vec2(0.0, -eps), t);

        // Gradient points away from nearest cell centre
        vec2 grad = vec2(v_r - v_l, v_u - v_d);

        // Edge mask — peaks sharply at cell boundaries (where v_c is near voronoi_border)
        float edge = 1.0 - smoothstep(0.0, voronoi_border, v_c);

        // Warp wrapped_uv — strong displacement scaled by strength and edge intensity
        vec2 distorted_uv = wrapped_uv + grad * edge * voronoi_strength * 0.4;

        // Also push the underlying uv used by later effects
        uv += grad * edge * voronoi_strength * 0.15;

        tex.rgb = texture(TEXTURE, fract(distorted_uv)).rgb;
    }
	
// --- JULIA SET ---
if (julia_strength > 0.001) {
    float spd = sync_speed(julia_speed);
    float t   = manual_time * PI * 2.0 * spd;
    
    // Animate c parameter in a circle for continuous morphing
    vec2 c = vec2(
        julia_cx * cos(t) - julia_cy * sin(t),
        julia_cx * sin(t) + julia_cy * cos(t)
    );
    
    // Map UV to complex plane
    vec2 z = (uv - 0.5) * 2.5 * julia_zoom;
    
    float iter = 0.0;
    for (int i = 0; i < julia_iterations; i++) {
        if (dot(z, z) > 4.0) break;
        z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        iter += 1.0;
    }
    
    // Smooth coloring
    float smooth_iter = iter / float(julia_iterations);
    
    // Use fractal pattern to distort UV
    vec2 julia_uv = uv + vec2(
        sin(smooth_iter * PI * 4.0) * 0.05,
        cos(smooth_iter * PI * 4.0) * 0.05
    ) * julia_strength;
    
    vec4 julia_tex = texture(TEXTURE, fract(julia_uv));
    
    // Blend fractal coloring with image
    tex.rgb = mix(tex.rgb, julia_tex.rgb * (1.0 - smooth_iter), julia_strength * smooth_iter);
}


	
	// --- NEWTON FRACTAL ---
if (newton_strength > 0.001) {
    float spd = sync_speed(newton_speed);
    float t   = manual_time * PI * 2.0 * spd;
    
    // Map UV to complex plane, rotate over time
    vec2 z = (uv - 0.5) * 2.5 * newton_zoom;
    float ca = cos(t);
    float sa = sin(t);
    z = vec2(z.x * ca - z.y * sa, z.x * sa + z.y * ca);
    
    // Iterate
    vec3 basin = newton_iterate(z, newton_iterations);
    
    // Mix fractal color with image
    // newton_color_mix controls how much the basin colors show vs image colors
    vec3 colored = mix(tex.rgb, tex.rgb * basin * 2.0, newton_color_mix);
    tex.rgb = mix(tex.rgb, colored, newton_strength);
}
	// =========================================================================
	// MASK & FINAL OUTPUT
	// =========================================================================

	vec2  mask_uv     = UV - 0.5;
	// Clamp stretch to avoid divide-by-zero — use abs so negative still works
	float safe_stretch = max(abs(mask_stretch), 0.01) * sign(mask_stretch + 0.001);
	mask_uv.x        *= safe_stretch;
	float dist_center = length(mask_uv);
	float feather      = 0.05;
	float mask         = smoothstep(mask_radius, mask_radius - feather, dist_center);

	tex.rgb *= mask;
	tex.a   *= mask;

	float edge_glow_ring = smoothstep(mask_radius - 0.02, mask_radius, dist_center) * mask;
	tex.rgb             += base_color.rgb * edge_glow_ring * 0.5;

	if (abs(mask_radius - dist_center) < 0.05) {
		float fringe   = smoothstep(0.05, 0.0, abs(mask_radius - dist_center));
		float r_fringe = texture(TEXTURE, wrapped_uv + (mask_uv * 0.01 * fringe)).r;
		float b_fringe = texture(TEXTURE, wrapped_uv - (mask_uv * 0.01 * fringe)).b;
		tex.rgb = mix(tex.rgb, vec3(r_fringe, tex.g, b_fringe), fringe * 0.5);
	}

	COLOR = vec4(tex.rgb, tex.a * base_color.a);
}
