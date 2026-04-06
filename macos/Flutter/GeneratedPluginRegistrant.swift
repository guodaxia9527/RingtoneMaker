//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_decoder
import audio_session
import file_picker
import just_audio
import open_file_mac
import share_plus

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioDecoderPlugin.register(with: registry.registrar(forPlugin: "AudioDecoderPlugin"))
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  JustAudioPlugin.register(with: registry.registrar(forPlugin: "JustAudioPlugin"))
  OpenFilePlugin.register(with: registry.registrar(forPlugin: "OpenFilePlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
}
