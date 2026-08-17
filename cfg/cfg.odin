package cfg

import "core:encoding/json"
import "core:fmt"
import "core:os"

// vulkan stuff
APPLICATION_NAME :: "aqua-omega-attack"
ENGINE_NAME      :: "aqua-omega-attack"
// win32 stuff
WINDOW_TITLE     :: "aqua-omega-attack"
WINDOW_CLASS 	 :: "aoa-overlay"
// for build.ps1
EXE_NAME	 	 :: "aqua-omega-attack"

Color :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

Config :: struct {
	esp: struct {
		enabled:      bool,
		name:         bool,
		box:          bool,
		skeleton:     bool,
		health_bar:   bool,
		health_point: bool,
		weapon:       bool,
		ammo:         bool,
		c4:           bool,
		spectators:   bool,
		spectators_x: f32,
		spectators_y: f32,
		reloading:    bool,
		scoping:      bool,
		defusing:     bool,
		flashed:      bool,
	},
	display: struct {
		name_max:      int,
		font_size:     f32,
		esp_font_size: f32,
	},
	engine: struct {
		tick_ms:   i64,
		fps_limit: i64,
	},
	colors: struct {
		box:          Color,
		skeleton:     Color,
		text:         Color,
		text_outline: Color,
		health:       Color,
		c4:           Color,
	},
}

default_config :: proc () -> Config {
	return Config {
		esp = {
			enabled      = true,
			name         = true,
			box          = false,
			skeleton     = true,
			health_bar   = true,
			health_point = false,
			weapon       = true,
			ammo         = true,
			c4           = true,
			spectators   = true,
			spectators_x = 156,
			spectators_y = 492,
			reloading    = true,
			scoping      = true,
			defusing     = true,
			flashed      = true,
		},
		display = {
			name_max      = 10,
			font_size     = 1,
			esp_font_size = 1.3,
		},
		engine = {
			tick_ms   = 18,
			fps_limit = 128,
		},
		colors = {
			box          = {255, 0,   0,   255},
			skeleton     = {4,   250, 255, 100},
			text         = {255, 255, 255, 255},
			text_outline = {0,   0,   0,   255},
			health       = {0,   255, 0,   100},
			c4           = {255, 140, 0,   255},
		},
	}
}

settings: Config

load :: proc () {
	settings = default_config()

	data, err := os.read_entire_file("Config.json", context.temp_allocator)
	if err != nil {
		fmt.println("no Config.json found, using defaults")
		return
	}

	if uerr := json.unmarshal(
		data, &settings,
		json.DEFAULT_SPECIFICATION,
		context.temp_allocator,
	); uerr != nil {
		fmt.eprintln("failed to unmarshal Config.json, using defaults:", uerr)
		settings = default_config()
		return
	}

	fmt.println("loaded Config.json")
}

save :: proc () {
	data, err := json.marshal(
		settings, {pretty = true, spec = .JSON}, context.temp_allocator)
	if err != nil {
		fmt.eprintln("failed to marshal config:", err)
		return
	}

	if werr := os.write_entire_file("Config.json", data); werr != nil {
		fmt.eprintln("failed to write Config.json:", werr)
		return
	}
	// fmt.println("saved Config.json")
}

font_path :: proc () -> string {
	candidates := []string {
		"C:\\Windows\\Fonts\\msyh.ttc",
		"C:\\Windows\\Fonts\\msyh.ttf",
		"C:\\Windows\\Fonts\\msyhl.ttc",
		"C:\\Windows\\Fonts\\simhei.ttf",
		"C:\\Windows\\Fonts\\simsun.ttc",
		"C:\\Windows\\Fonts\\segoeui.ttf",
	}
	for candidate in candidates {
		if os.exists(candidate) {
			return candidate
		}
	}
	return ""
}
