package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:strconv"
import "core:strings"
import "core:text/regex"

Mode :: struct {
	width:   string,
	height:  string,
	refresh: string,
}

main :: proc() {

	// https://gist.github.com/karl-zylinski/4ccf438337123e7c8994df3b03604e33
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	if len(os.args) < 2 || !strings.contains(os.args[1:][0], "--path:") {
		fmt.println("Error no niri config path provided like '--path:niri_config_path'")
		return
	}

	path := os.args[1:][0][7:]

	file, err := os.open(path, os.O_RDWR | os.O_APPEND)
	defer os.close(file)
	if err != nil {
		fmt.println("Error no valid file at path ", path)
		return
	}

	data, err2 := os.read_entire_file_from_handle_or_err(file)
	defer delete(data)
	if err2 != nil {
		fmt.println("Error reading the file")
		return
	}

	state, stdout, stderr, err3 := os2.process_exec(
		os2.Process_Desc{command = []string{"niri", "msg", "outputs"}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err3 != nil {
		fmt.println("Error command 'niri msg outputs' failed")
		return
	}

	lines := strings.split(string(stdout), "\n")
	defer delete(lines)

	outputs := make(map[string]Mode)
	defer delete(outputs)

	output_name: string

	max_width: int
	max_height: int
	max_pixels: int
	max_refresh: f64

	max_width_str: string
	max_height_str: string
	max_refresh_str: string

	rg, _ := regex.create_by_user(`/Output.+?\((.+?)\)/`)
	defer regex.destroy_regex(rg)
	rg2, _ := regex.create_by_user(`/(\d+)x(\d+)@(\d+\.\d+)/`)
	defer regex.destroy_regex(rg2)

	for i := 0; i < len(lines); i += 1 {
		capture, _ := regex.match(rg, lines[i])
		if len(capture.groups) > 0 {
			output_name = capture.groups[1]
		}
		regex.destroy(capture)
		if len(output_name) == 0 {continue}
		capture, _ = regex.match(rg2, lines[i])
		defer regex.destroy(capture)
		if len(capture.groups) > 0 {

			width := strconv.atoi(capture.groups[1])
			height := strconv.atoi(capture.groups[2])
			pixels := width * height
			refresh := strconv.atof(capture.groups[3])

			if pixels >= max_pixels && refresh >= max_refresh {
				max_width = width
				max_height = height
				max_pixels = pixels
				max_refresh = refresh

				max_width_str = capture.groups[1]
				max_height_str = capture.groups[2]
				max_refresh_str = capture.groups[3]
			} else {
				outputs[output_name] = Mode{max_width_str, max_height_str, max_refresh_str}

				output_name = ""

				max_width = 0
				max_height = 0
				max_pixels = 0
				max_refresh = 0

				max_width_str = ""
				max_height_str = ""
				max_refresh_str = ""
			}
		}
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	for output in outputs {
		mode := outputs[output]
		output_str := strings.concatenate(
			{
				"\n\noutput \"",
				output,
				"\" {\n    mode \"",
				mode.width,
				"x",
				mode.height,
				"@",
				mode.refresh,
				"\"\n}",
			},
		)
		defer delete(output_str)
		strings.write_string(&b, output_str)
	}

	final_str := strings.to_string(b)

	if len(final_str) == 0 {
		fmt.println("Failed to build valid outputs")
		return
	}

	os.write_string(file, final_str)

	fmt.println("Config updated!")
}
