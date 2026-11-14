extends SceneTree
## Rebuilds notices from the exact Godot binary used for the game release.
## Run: godot --headless --script tools/export_licenses.gd -- /absolute/output.md


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the absolute THIRD_PARTY_NOTICES.md output path after --")
		quit(1)
		return
	var output := "# Third-party notices\n\n"
	output += "This game bundles the Godot Engine and Noto Sans SC font. "
	output += "The game source has its own MIT license in LICENSE.\n\n"
	output += "Engine version: `%s`.\n\n" % Engine.get_version_info().get("string", "unknown")
	output += "The engine notices below were extracted directly from the release's "
	output += "Godot editor binary used to build this release, using Engine.get_license_text(), Engine.get_copyright_info(), "
	output += "and Engine.get_license_info(). Godot reports its compiled component notices "
	output += "together; some listed components may only be used by particular features.\n\n"
	output += "## Noto Sans SC\n\n"
	output += "(c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.\n\n"
	output += "Licensed under the SIL Open Font License, Version 1.1. "
	output += "The unmodified font includes its original metadata. "
	output += "The full license and font notice accompany the game as "
	output += "`licenses/OFL.txt` and `licenses/NOTICE.txt`; in the source project they are "
	output += "`射击游戏/assets/fonts/OFL.txt` and `射击游戏/assets/fonts/NOTICE.txt`.\n\n"
	output += "Project: https://github.com/notofonts/noto-cjk\n\n"
	output += "## Godot Engine license\n\n```text\n"
	output += Engine.get_license_text().strip_edges() + "\n```\n\n"
	output += "## Godot component attributions\n\n"
	for component: Dictionary in Engine.get_copyright_info():
		output += "### %s\n\n" % str(component.get("name", "Unnamed component"))
		for part: Dictionary in component.get("parts", []):
			output += "License expression: `%s`\n\n" % str(part.get("license", ""))
			output += "```text\n"
			for notice: String in part.get("copyright", []):
				output += notice + "\n"
			output += "```\n\n"
	output += "## Godot component license texts\n\n"
	var licenses: Dictionary = Engine.get_license_info()
	var license_names: Array = licenses.keys()
	license_names.sort()
	for license_name: String in license_names:
		output += "### %s\n\n```text\n" % license_name
		output += str(licenses[license_name]).strip_edges() + "\n```\n\n"
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write notices: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(output)
	file.close()
	print("Third-party notices written: %s (%d characters)" % [args[0], output.length()])
	quit(0)
