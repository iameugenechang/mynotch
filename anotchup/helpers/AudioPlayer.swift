//
//  AudioPlayer.swift
//  anotchup
//
//  Created by Harsh Vardhan  Goswami  on 09/08/24.
//

import Foundation
import AppKit
import Defaults

@MainActor
final class OneGoalSoundPlayer {
    static let shared = OneGoalSoundPlayer()
    private var sound: NSSound?

    func playSelectedSound() {
        sound?.stop()
        sound = nil
        let selection = Defaults[.oneGoalCompletionSound]
        guard selection != .silent else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(selection.rawValue).aiff")
        guard let selectedSound = NSSound(contentsOf: url, byReference: false) else { return }
        selectedSound.volume = Float(min(1, max(0, Defaults[.oneGoalSoundVolume])))
        sound = selectedSound
        selectedSound.play()
    }
}

class AudioPlayer {
    func play(fileName: String, fileExtension: String) {
        NSSound(contentsOf:Bundle.main.url(forResource: fileName, withExtension: fileExtension)!, byReference: false)?.play()
    }
}
