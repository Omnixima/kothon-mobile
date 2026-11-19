// The typing keys as one UIKit view, the way fast keyboards do it: keys are
// laid out once, a touch is matched to a key by position and acts on
// touch-down, several fingers can be down at once (rollover), and a press
// only recolors that one key. SwiftUI only rebuilds the grid when the
// layout changes (shift, ১২৩, language), never per keystroke.

import SwiftUI
import UIKit

struct KeySpec: Equatable {
    enum Style: Equatable { case letter, special, specialOn, space, blank }
    enum Width: Equatable { case flex, fixed(CGFloat) }

    var id: String           // what the key does, e.g. "ch:ক", "shift", "del"
    var label: String = ""
    var symbol: String?      // SF Symbol instead of a label
    var style: Style = .letter
    var width: Width = .flex
    var repeats = false      // delete: repeats while held
    var accessibility: String?
}

struct KeyRow: Equatable {
    var keys: [KeySpec]
    var inset: CGFloat = 0   // QWERTY's inset middle row
}

/// SwiftUI wrapper. `onKey` gets the key's id on touch-down.
struct KeyGrid: UIViewRepresentable {
    let rows: [KeyRow]
    var topGap: CGFloat = 0
    var showHitAreas = false
    let onKey: (String) -> Void

    func makeUIView(context: Context) -> KeyGridView {
        let v = KeyGridView()
        v.onKey = onKey
        v.topGap = topGap
        v.showHitAreas = showHitAreas
        v.rows = rows
        return v
    }

    func updateUIView(_ v: KeyGridView, context: Context) {
        v.onKey = onKey
        if v.topGap != topGap { v.topGap = topGap }
        if v.showHitAreas != showHitAreas { v.showHitAreas = showHitAreas }
        if v.rows != rows { v.rows = rows }
    }
}

final class KeyGridView: UIView, UIInputViewAudioFeedback {
    var onKey: (String) -> Void = { _ in }
    var rows: [KeyRow] = [] { didSet { rebuild() } }
    /// Space above the first row that still belongs to it (the gap under
    /// the dictation button), so no tap in the key area is lost.
    var topGap: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// Developer mode: tint each key's tap area to check there are no gaps.
    var showHitAreas = false { didSet { setNeedsLayout() } }
    private var hitOverlays: [UIView] = []
    /// People tap a little below a key's middle; look this much higher
    /// when picking the row, as system keyboards do.
    private static let touchLift: CGFloat = 5

    var enableInputClicksWhenVisible: Bool { true }

    private struct Cell {
        let spec: KeySpec
        let view: UIView
        var hitFrame: CGRect = .zero
    }
    private var cells: [Cell] = []
    /// Which key each finger is on.
    private var touchKeys: [ObjectIdentifier: Int] = [:]
    private var repeatTimer: Timer?

    private static let inset = CGSize(width: 2.5, height: 4)
    private static let bengaliFont: (CGFloat, UIFont.Weight) -> UIFont = { size, weight in
        let d = UIFontDescriptor(fontAttributes: [.family: Brand.fontName])
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: d, size: size)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Build and lay out

    private func rebuild() {
        stopRepeat()
        touchKeys.removeAll()
        cells.forEach { $0.view.removeFromSuperview() }
        cells = rows.flatMap { $0.keys }.map { Cell(spec: $0, view: makeKeyView($0)) }
        cells.forEach { addSubview($0.view) }
        setNeedsLayout()
    }

    private func makeKeyView(_ spec: KeySpec) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.layer.cornerRadius = 8
        v.layer.cornerCurve = .continuous
        v.backgroundColor = background(spec, pressed: false)
        if let symbol = spec.symbol {
            let iv = UIImageView(image: UIImage(systemName: symbol,
                                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)))
            iv.tintColor = .label
            iv.contentMode = .center
            v.addSubview(iv)
        } else {
            let l = UILabel()
            l.text = spec.label
            l.textAlignment = .center
            l.textColor = .label
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.6
            l.font = spec.style == .letter
                ? Self.bengaliFont(21, .regular)
                : Self.bengaliFont(spec.style == .space ? 15 : 15, .medium)
            v.addSubview(l)
        }
        v.isAccessibilityElement = true
        v.accessibilityLabel = spec.accessibility ?? (spec.label.isEmpty ? spec.id : spec.label)
        v.accessibilityTraits = .keyboardKey
        return v
    }

    private func background(_ spec: KeySpec, pressed: Bool) -> UIColor {
        switch spec.style {
        case .letter, .space:
            return pressed ? .systemGray3 : .secondarySystemBackground
        case .special:
            return UIColor(Brand.violet).withAlphaComponent(pressed ? 0.45 : 0.16)
        case .specialOn:
            return UIColor(Brand.violet).withAlphaComponent(0.45)
        case .blank:
            return .clear
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        removeSystemTouchDelays()
        guard !rows.isEmpty else { return }
        let rowH = (bounds.height - topGap) / CGFloat(rows.count)
        var i = 0
        for (r, row) in rows.enumerated() {
            let y = topGap + CGFloat(r) * rowH
            let avail = bounds.width - 2 * row.inset
            let fixed = row.keys.reduce(CGFloat(0)) { if case .fixed(let w) = $1.width { return $0 + w }; return $0 }
            let flexCount = CGFloat(row.keys.filter { $0.width == .flex }.count)
            let flexW = flexCount > 0 ? max(0, avail - fixed) / flexCount : 0
            var x = row.inset
            for (k, spec) in row.keys.enumerated() {
                let w: CGFloat = { if case .fixed(let w) = spec.width { return w }; return flexW }()
                // The tap area reaches into the gaps; the first and last key
                // also cover the row's inset.
                var hit = CGRect(x: x, y: y, width: w, height: rowH)
                if k == 0 { hit = CGRect(x: 0, y: y, width: x + w, height: rowH) }
                if k == row.keys.count - 1 { hit.size.width = bounds.width - hit.minX }
                cells[i].hitFrame = hit
                cells[i].view.frame = CGRect(x: x, y: y, width: w, height: rowH)
                    .insetBy(dx: Self.inset.width, dy: Self.inset.height)
                // The label or icon fills its key, centred.
                cells[i].view.subviews.forEach { $0.frame = cells[i].view.bounds }
                x += w
                i += 1
            }
        }
        layoutHitOverlays()
    }

    private func layoutHitOverlays() {
        hitOverlays.forEach { $0.removeFromSuperview() }
        hitOverlays = []
        guard showHitAreas else { return }
        let rowH = (bounds.height - topGap) / CGFloat(max(rows.count, 1))
        for (n, c) in cells.enumerated() {
            var f = c.hitFrame
            if f.minY <= topGap + 0.5 { f = CGRect(x: f.minX, y: 0, width: f.width, height: f.maxY) }  // first row's band
            _ = rowH
            let o = UIView(frame: f)
            o.isUserInteractionEnabled = false
            o.backgroundColor = (n % 2 == 0 ? UIColor.systemPink : UIColor.systemTeal).withAlphaComponent(0.25)
            o.layer.borderWidth = 0.5
            o.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            addSubview(o)
            hitOverlays.append(o)
        }
    }

    // MARK: Touches

    /// Every point maps to a key, as on Gboard: the row by height (each
    /// row's band runs to the middle of the gaps, the first up into the gap
    /// under the dictation button, the last to the bottom edge), then the
    /// key in that row by x, or the nearest one. Blank cells never win.
    private func cellIndex(at p: CGPoint) -> Int? {
        guard !rows.isEmpty, !cells.isEmpty else { return nil }
        let rowH = (bounds.height - topGap) / CGFloat(rows.count)
        let y = p.y - Self.touchLift - topGap
        let r = min(max(Int((y / rowH).rounded(.down)), 0), rows.count - 1)
        let start = rows[..<r].reduce(0) { $0 + $1.keys.count }
        let rowCells = Array(start..<(start + rows[r].keys.count))
        let usable = rowCells.filter { cells[$0].spec.style != .blank }
        if let hit = usable.first(where: { p.x >= cells[$0].hitFrame.minX && p.x < cells[$0].hitFrame.maxX }) {
            return hit
        }
        return usable.min { abs(cells[$0].hitFrame.midX - p.x) < abs(cells[$1].hitFrame.midX - p.x) }
    }

    // Taps a little outside the grid (its edges) still count.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -4).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let i = cellIndex(at: t.location(in: self)) else { continue }
            touchKeys[ObjectIdentifier(t)] = i
            setPressed(i, true)
            fire(i)
            if cells[i].spec.repeats { startRepeat(i) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }

    private func release(_ touches: Set<UITouch>) {
        for t in touches {
            if let i = touchKeys.removeValue(forKey: ObjectIdentifier(t)) {
                setPressed(i, false)
                if cells.indices.contains(i), cells[i].spec.repeats { stopRepeat() }
            }
        }
    }

    private func fire(_ i: Int) {
        guard cells.indices.contains(i) else { return }
        let id = cells[i].spec.id
        onKey(id)
        UIDevice.current.playInputClick()
    }

    private func setPressed(_ i: Int, _ on: Bool) {
        guard cells.indices.contains(i) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cells[i].view.backgroundColor = background(cells[i].spec, pressed: on)
        CATransaction.commit()
    }

    private func startRepeat(_ i: Int) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, self.cells.indices.contains(i) else { return }
                self.onKey(self.cells[i].spec.id)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // Rows change (shift, ১২৩) while a finger may still be down.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopRepeat(); touchKeys.removeAll() }
        removeSystemTouchDelays()
    }

    /// The keyboard's window carries iOS's screen-edge and home-indicator
    /// gesture recognizers, which hold every touch back for a moment
    /// (delaysTouchesBegan/Ended) before the keys see it; worst on the bottom
    /// row and the edges. Fast keyboards turn those delays off on every
    /// recognizer from the keys up to the window. The recognizers still work.
    /// Re-applied on every layout: iOS can add recognizers after appear.
    func removeSystemTouchDelays() {
        guard window != nil else { return }
        var v: UIView? = self
        while let current = v {
            for g in current.gestureRecognizers ?? [] {
                g.delaysTouchesBegan = false
                g.delaysTouchesEnded = false
            }
            v = current.superview
        }
    }
}
