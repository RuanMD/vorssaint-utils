// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScreenAnnotationTests {
    static func run(_ suite: TestSuite) {
        let rawPoints = (0..<(ScreenAnnotationSupport.maxPointsPerStroke + 20))
            .map { AnnotationPoint(x: Double($0), y: Double($0)) }
        let boundedStroke = AnnotationStroke(tool: .pen, color: .red, width: 100, points: rawPoints)
        suite.expect(boundedStroke.points.count == ScreenAnnotationSupport.maxPointsPerStroke,
               "annotation strokes cap their point count")
        suite.expect(boundedStroke.width == 40 && boundedStroke.color == .red,
               "annotation stroke values are clamped without changing color")
        suite.expect(AnnotationColor.orange != AnnotationColor.yellow,
               "annotation orange and yellow remain distinct colors")
        suite.expect(ScreenAnnotationSupport.append(AnnotationPoint(x: 0.0001, y: 0.0001), to: [AnnotationPoint(x: 0, y: 0)]).count == 1,
               "annotation input ignores subpixel noise")
        suite.expect(ScreenAnnotationSupport.append(AnnotationPoint(x: 0.01, y: 0.01), to: [AnnotationPoint(x: 0, y: 0)]).count == 2,
               "annotation input records ordinary drawing movement")
        suite.expect(ScreenAnnotationSupport.undo([boundedStroke]).isEmpty,
               "annotation undo removes only the last stroke")
        suite.expect(ScreenAnnotationSupport.clear([boundedStroke]).isEmpty,
               "annotation clear is idempotent")
        suite.expect(!ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: true)
                && ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: false),
               "annotation canvas captures only while drawing")
    }
}
