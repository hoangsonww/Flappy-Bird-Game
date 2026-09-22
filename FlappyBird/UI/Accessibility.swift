import SpriteKit
import UIKit

/// An `SKNode` VoiceOver can actually see.
///
/// Setting `isAccessibilityElement` on an `SKNode` publishes it to the
/// accessibility tree, but SpriteKit never derives `accessibilityFrame` from
/// the node — the inherited default is `.zero`. A zero-sized element cannot be
/// focused by the VoiceOver cursor, activated by assistive technology, or
/// tapped by `XCUITest`, so every accessible node has to convert its own bounds
/// into screen space itself. This does that once.
///
/// A node that is an accessibility element hides its children from the tree, so
/// only use it for leaves: a row that contains a button publishes the button
/// separately and describes its text with a sibling element instead.
class AccessibleNode: SKNode {

    /// The node's bounds in its own coordinate space, centred on its origin.
    var accessibleSize: CGSize = .zero

    override var accessibilityFrame: CGRect {
        get { screenFrame(ofSize: accessibleSize) }
        set { super.accessibilityFrame = newValue }
    }

    /// Publish this node with `label`, read as static text.
    @discardableResult
    func describe(_ label: String, size: CGSize, traits: UIAccessibilityTraits = .staticText) -> Self {
        accessibleSize = size
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = traits
        return self
    }
}

extension SKNode {

    /// `size`, centred on this node, in screen coordinates.
    ///
    /// Returns `.zero` while the node is off-scene, which correctly reads as
    /// "not currently on screen" rather than as a control at the origin.
    func screenFrame(ofSize size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, let scene, let view = scene.view else { return .zero }

        let corners = [
            CGPoint(x: -size.width / 2, y: -size.height / 2),
            CGPoint(x: size.width / 2, y: size.height / 2),
        ].map { view.convert(convert($0, to: scene), from: scene) }

        let rect = CGRect(
            x: min(corners[0].x, corners[1].x),
            y: min(corners[0].y, corners[1].y),
            width: abs(corners[1].x - corners[0].x),
            height: abs(corners[1].y - corners[0].y)
        )
        return UIAccessibility.convertToScreenCoordinates(rect, in: view)
    }
}

/// Join the parts of a row into one sentence for VoiceOver.
///
/// Rows read as "Best score, 58" rather than as four separate elements the
/// cursor has to walk through.
func accessibilitySentence(_ parts: String?...) -> String {
    parts
        .compactMap { $0 }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}
