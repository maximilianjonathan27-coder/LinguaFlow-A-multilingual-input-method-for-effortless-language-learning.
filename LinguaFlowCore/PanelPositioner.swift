import CoreGraphics

public enum PanelPositioner {
    public static func frame(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - panelSize.width)
        let x = min(max(anchor.minX, minimumX), maximumX)

        let belowY = anchor.minY - panelSize.height - gap
        let aboveY = anchor.maxY + gap
        let proposedY = belowY >= visibleFrame.minY ? belowY : aboveY
        let minimumY = visibleFrame.minY
        let maximumY = max(minimumY, visibleFrame.maxY - panelSize.height)
        let y = min(max(proposedY, minimumY), maximumY)

        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}
