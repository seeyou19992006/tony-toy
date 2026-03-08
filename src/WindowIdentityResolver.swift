import Foundation
import CoreGraphics

struct WindowListEntry: Equatable {
    let number: Int
    let ownerPID: pid_t
    let title: String?
    let frame: CGRect
    let layer: Int
}

enum WindowIdentityResolver {
    static func bestWindowNumber(
        processIdentifier: pid_t,
        title: String?,
        frame: CGRect,
        entries: [WindowListEntry]
    ) -> Int? {
        let normalizedTitle = normalized(title)
        let candidates = entries.filter { $0.ownerPID == processIdentifier && $0.layer == 0 }

        return candidates.min { lhs, rhs in
            sortScore(for: lhs, expectedTitle: normalizedTitle, expectedFrame: frame) <
            sortScore(for: rhs, expectedTitle: normalizedTitle, expectedFrame: frame)
        }?.number
    }

    static func entriesFromSystemWindowList() -> [WindowListEntry] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? Int,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }

            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let title = entry[kCGWindowName as String] as? String
            return WindowListEntry(
                number: number,
                ownerPID: pid_t(ownerPID),
                title: title,
                frame: bounds,
                layer: layer
            )
        }
    }

    private static func sortScore(for entry: WindowListEntry, expectedTitle: String?, expectedFrame: CGRect) -> CGFloat {
        let titlePenalty: Int
        if let expectedTitle, !expectedTitle.isEmpty {
            titlePenalty = normalized(entry.title) == expectedTitle ? 0 : 1
        } else {
            titlePenalty = 0
        }

        let framePenalty = abs(entry.frame.minX - expectedFrame.minX) +
            abs(entry.frame.minY - expectedFrame.minY) +
            abs(entry.frame.width - expectedFrame.width) +
            abs(entry.frame.height - expectedFrame.height)

        let areaPenalty = abs((entry.frame.width * entry.frame.height) - (expectedFrame.width * expectedFrame.height))
        return framePenalty + areaPenalty + CGFloat(titlePenalty) * 500
    }

    private static func normalized(_ title: String?) -> String? {
        title?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
