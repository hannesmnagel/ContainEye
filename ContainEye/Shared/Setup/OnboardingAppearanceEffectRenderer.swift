//
//  OnboardingAppearanceEffectRenderer.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct OnboardingAppearanceEffectRenderer: TextRenderer, Animatable {
    var elapsedTime: TimeInterval

    var elementDuration: TimeInterval

    var totalDuration: TimeInterval

    var spring: Spring {
        .snappy(duration: elementDuration - 0.05, extraBounce: 0.4)
    }

    var animatableData: Double {
        get { elapsedTime }
        set { elapsedTime = newValue }
    }
    init(elapsedTime: TimeInterval, elementDuration: Double = 1.5, totalDuration: TimeInterval) {
        self.elapsedTime = min(elapsedTime, totalDuration)
        self.elementDuration = min(elementDuration, totalDuration)
        self.totalDuration = totalDuration
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {

            let delay = elementDelay(count: run.count)

            for (index, slice) in run.enumerated() {
                let timeOffset = TimeInterval(index) * delay
                let elementTime = max(0, min(elapsedTime - timeOffset, elementDuration))

                var copy = context
                draw(slice, at: elementTime, in: &copy)
            }
        }
    }
    func draw(_ slice: Text.Layout.RunSlice, at time: TimeInterval, in context: inout GraphicsContext) {
        let progress = time / elementDuration

        let opacity = UnitCurve.easeIn.value(at: 1.4 * progress)

        let blurRadius =
        slice.typographicBounds.rect.height / 16 *
        UnitCurve.easeIn.value(at: 1 - progress)

        // The y-translation derives from a spring, which requires a
        // time in seconds.
        let translationY = spring.value(
            fromValue: -slice.typographicBounds.descent,
            toValue: 0,
            initialVelocity: 0,
            time: time)

        context.translateBy(x: 0, y: translationY)
        context.addFilter(.blur(radius: blurRadius))
        context.opacity = opacity
        context.draw(slice, options: .disablesSubpixelQuantization)
    }

    func elementDelay(count: Int) -> TimeInterval {
        let count = TimeInterval(count)
        let remainingTime = totalDuration - count * elementDuration

        return max(remainingTime / (count + 1), (totalDuration - elementDuration) / count)
    }

}

extension Text.Layout {
    var flattenedRuns: some RandomAccessCollection<Text.Layout.Run> {
        self.flatMap { line in
            line
        }
    }

    var flattenedRunSlices: some RandomAccessCollection<Text.Layout.RunSlice> {
        flattenedRuns.flatMap(\.self)
    }
}
