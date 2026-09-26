Closed Beta README (readable inside APP, select "⚙️" then "HELP")
APP NAME = Thinking of name still, leaning towards "Trippy H. Art Toolkit or "T.H.A.T." for short..
sorta rolls funny off of the tongue, so...

**THATv2** What is it?
* A shader sandbox that lets users design and save combinations of patterns & effects
	* A shader is a small computer program that runs on a graphics processing unit (GPU) to calculate the color, light, and shape of images on a screen.

* APP lets users design effects that only take place when switching between saved presets.
* A screensaver mode = Once you have at least 2 - saved presets and 1 transition preset, you can toggle the screensaver ON.

**BASIC CONTROLS**

* ← & → = modifies values inside a menu row
* ↑ & ↓ = scroll through menu lists
* ✔️= Confirms a menu selection
* ❌= Cancels or returns from a menu
* 🎛= Opens the Lab or the Transition Lab (where we customize the pattern, or transition style)
* ⚙️= Opens the Main Menu (Contains "screensaver dev" mode toggle, a help menu, a controller layout menu, and a colors menu for choosing background/button color")
* ❤️= Toggles on FPS/VRAM monitor (shows frames per second & virtual memory usage, green=low,yellow=mid,red=high)
 
**KEY INFORMATION**

* In the 🎛 Labs, you can only choose ONE base pattern, or ONE filter
* You can choose any number of EFFECTS in "pass 2", and they stack on top of one another
	* Example, if you add a swirl effect before a kaleidoscope, it would be appear different than adding a kaleidoscope before a swirl
* You can customize your button layout & background colors, those option are inside of ⚙️ 


**ADVANCED CONTROLS**

* Save a pattern preset = Open ⚙️ and select "presets", then click SAVE
	* (tip: customize a pattern first)

* Screensaver Dev Mode:
	
	1) Open ⚙️ and toggle "screensaver dev mode" ON 
	2) Exit the menu.  You are now in screensaver dev mode. 
	3) Pressing the 🎛 opens "transition editor menu"
	4) Select & Configure the formulas (you can select any number of formulas here)
	5) To try it out, exit the menu
	
* When in Screensaver Dev Mode, additional controls are active:
	
	a) ← & → will transition between pattern presets (you must have at least two saved)
	b) ↑ & ↓ will increase/decrease the duration of the transition (this duration will be saved, it is unique to each transition you create)
	c) ✔️ button will offer open the SAVE menu for transitions
	d) To load a saved transition, open the 🎛 lab, and scroll to the bottom to find the option "LOAD"
	e) Currently, the best looking transitions I've made feature the options, but feel free to experiment
	
		a) fisheye
		b) swirl
		c) pixelate
		
* Once you have saved a transition you can enable Screensaver Mode, which will automatically choose a random saved preset and a random saved transition

## License

This project is free software. It is licensed under the [GNU General Public License v3.0](LICENSE) or any later version.
### What you can do:
* **Run:** You can run the app for any purpose.
* **Study:** You can look at the source code to see how it works. (once released, find it on my git page here : https://github.com/ocybin-solo)
* **Modify:** You can change the code to add features or fix bugs.
* **Share:** You can make copies of the original or modified app and give them to others.
### The main rule (Copyleft):
* If you distribute your modified version of this app, you **must** also license it under the same GNU GPL terms. You must make your source code freely available to others as well. 
*(Note: While the original concept was inspired by an older project under the permissive MIT license (FREE SHADER APP, also on my GIT page), this entire codebase was written completely from scratch. This new version is fully bound by the terms of the GNU GPL.)*

## Authors & Acknowledgments

### Tools & Engine

Godot Engine  **  (https://godotengine.org/) (v4.7.2)  ** - This application was fully designed and built using the Godot Engine. Godot is free software distributed under the terms of the MIT License. See the official [Godot License Page](https://godotengine.org/license/) for full copyright notices and third-party components.

### AI Collaborators
This project was developed with the assistance of the following AI tools (free versions):
	
* Gemini AI - Assisted primarily with web research, documentation, and conceptual guidance.
* Claude AI - Assisted primarily with code debugging and refactoring major architectural changes.
* ChatGPT AI - Assisted with developing the shaders

While AI tools were used for research and code generation, all architectural decisions, final integrations, testing and review were performed by the primary author.

**Lead Author, Core Architect, and Developer** 
JEFF BOX / OCYBIN : on the web @ https://github.com/ocybin-solo
