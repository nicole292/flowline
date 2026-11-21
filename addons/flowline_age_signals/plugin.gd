@tool
extends EditorPlugin
## Adds the age-signals Android plugin (bin/flowline-age-signals.aar, built by
## tools/android/build_age_signals.sh) and Google's Play Age Signals library
## to Android exports. Needs the Gradle build (preset "Android Play").

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = AgeSignalsExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AgeSignalsExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "FlowlineAgeSignals"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/flowline_age_signals/bin/flowline-age-signals.aar"])

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.android.play:age-signals:0.0.6"])
