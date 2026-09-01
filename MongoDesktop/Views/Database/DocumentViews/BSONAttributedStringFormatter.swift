import SwiftUI
import SwiftBSON

// MARK: - BSONAttributedStringFormatter

struct BSONAttributedStringFormatter {
    var timeZone: TimeZone = .current
    var indentSpaces: Int = 2
    var expandedPaths: Set<String> = []

    // Syntax Highlighting Colors
    var keyColor: Color = Color(red: 0.4, green: 0.7, blue: 1.0)
    var stringColor: Color = Color(red: 0.8, green: 0.6, blue: 0.3)
    var numberColor: Color = Color(red: 0.6, green: 0.85, blue: 0.7)
    var boolColor: Color = Color(red: 0.4, green: 0.85, blue: 0.5)
    var nullColor: Color = Color(red: 0.7, green: 0.4, blue: 0.4)
    var specialColor: Color = .orange
    var punctuationColor: Color = .secondary
    var chevronColor: Color = .accentColor

    func format(document: BSONDocument, basePath: String = "") -> AttributedString {
        var output = AttributedString()
        appendDocument(document, into: &output, depth: 0, currentPath: basePath)
        return output
    }

    private func appendDocument(
        _ doc: BSONDocument,
        into output: inout AttributedString,
        depth: Int,
        currentPath: String
    ) {
        if doc.isEmpty {
            output.append(styled("{}", color: punctuationColor))
            return
        }

        output.append(styled("{\n", color: punctuationColor))
        let pairs = Array(doc)

        for (idx, pair) in pairs.enumerated() {
            let childPath = currentPath.isEmpty ? pair.key : "\(currentPath).\(pair.key)"
            let hasChildren = valueHasChildren(pair.value)
            let isExpanded = hasChildren && expandedPaths.contains(childPath)

            let baseIndent = String(repeating: " ", count: depth * indentSpaces)

            if hasChildren {
                let symbol = isExpanded ? "▾ " : "▸ "
                output.append(AttributedString(baseIndent))
                output.append(makeFoldLink(path: childPath, symbol: symbol))
            } else {
                output.append(AttributedString(baseIndent + String(repeating: " ", count: indentSpaces)))
            }

            output.append(styled("\"\(escapeJSONString(pair.key))\"", color: keyColor))
            output.append(styled(": ", color: punctuationColor))

            if hasChildren && !isExpanded {
                let placeholder = collapsedSummary(for: pair.value)
                output.append(makePlaceholderLink(path: childPath, text: placeholder))
            } else {
                appendValue(pair.value, into: &output, depth: depth + 1, currentPath: childPath)
            }

            if idx < pairs.count - 1 {
                output.append(styled(",", color: punctuationColor))
            }
            output.append(AttributedString("\n"))
        }

        let closingIndent = String(repeating: " ", count: depth * indentSpaces)
        output.append(AttributedString(closingIndent))
        output.append(styled("}", color: punctuationColor))
    }

    private func appendArray(
        _ array: [BSON],
        into output: inout AttributedString,
        depth: Int,
        currentPath: String
    ) {
        if array.isEmpty {
            output.append(styled("[]", color: punctuationColor))
            return
        }

        output.append(styled("[\n", color: punctuationColor))

        for (idx, item) in array.enumerated() {
            let childPath = "\(currentPath)[\(idx)]"
            let hasChildren = valueHasChildren(item)
            let isExpanded = hasChildren && expandedPaths.contains(childPath)

            let baseIndent = String(repeating: " ", count: depth * indentSpaces)

            if hasChildren {
                let symbol = isExpanded ? "▾ " : "▸ "
                output.append(AttributedString(baseIndent))
                output.append(makeFoldLink(path: childPath, symbol: symbol))
            } else {
                output.append(AttributedString(baseIndent + String(repeating: " ", count: indentSpaces)))
            }

            if hasChildren && !isExpanded {
                let placeholder = collapsedSummary(for: item)
                output.append(makePlaceholderLink(path: childPath, text: placeholder))
            } else {
                appendValue(item, into: &output, depth: depth + 1, currentPath: childPath)
            }

            if idx < array.count - 1 {
                output.append(styled(",", color: punctuationColor))
            }
            output.append(AttributedString("\n"))
        }

        let closingIndent = String(repeating: " ", count: depth * indentSpaces)
        output.append(AttributedString(closingIndent))
        output.append(styled("]", color: punctuationColor))
    }

    private func appendValue(
        _ value: BSON,
        into output: inout AttributedString,
        depth: Int,
        currentPath: String
    ) {
        switch value {
        case .document(let doc):
            appendDocument(doc, into: &output, depth: depth, currentPath: currentPath)
        case .array(let arr):
            appendArray(arr, into: &output, depth: depth, currentPath: currentPath)
        case .string(let s):
            output.append(styled("\"\(escapeJSONString(s))\"", color: stringColor))
        case .int32(let i):
            output.append(styled("\(i)", color: numberColor))
        case .int64(let i):
            output.append(styled("\(i)", color: numberColor))
        case .double(let d):
            output.append(styled("\(d)", color: numberColor))
        case .decimal128(let dec):
            output.append(styled("NumberDecimal(\"\(dec)\")", color: specialColor))
        case .bool(let b):
            output.append(styled(b ? "true" : "false", color: boolColor))
        case .null:
            output.append(styled("null", color: nullColor))
        case .objectID(let id):
            output.append(styled("ObjectId(\"\(id)\")", color: specialColor))
        case .datetime(let d):
            displayDateFormatter.timeZone = timeZone
            let formattedDate = displayDateFormatter.string(from: d)
            output.append(styled("ISODate(\"\(formattedDate)\")", color: specialColor))
        case .binary(let bin):
            if let uuid = try? bin.toUUID() {
                output.append(styled("UUID(\"\(uuid.uuidString.lowercased())\")", color: specialColor))
            } else {
                output.append(styled(String(describing: value), color: specialColor))
            }
        case .regex(let r):
            output.append(styled("/\(r.pattern)/\(r.options)", color: specialColor))
        case .timestamp:
            output.append(styled(String(describing: value), color: specialColor))
        case .minKey:
            output.append(styled("MinKey", color: specialColor))
        case .maxKey:
            output.append(styled("MaxKey", color: specialColor))
        default:
            output.append(styled(String(describing: value), color: stringColor))
        }
    }

    private func valueHasChildren(_ value: BSON) -> Bool {
        switch value {
        case .document(let doc):
            return !doc.isEmpty
        case .array(let arr):
            return !arr.isEmpty
        default:
            return false
        }
    }

    private func collapsedSummary(for value: BSON) -> String {
        switch value {
        case .document(let doc):
            return "{ \(doc.count) fields }"
        case .array(let arr):
            return "[ \(arr.count) items ]"
        default:
            return "..."
        }
    }

    private func makeFoldLink(path: String, symbol: String) -> AttributedString {
        var str = AttributedString(symbol)
        str.foregroundColor = chevronColor
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        str.link = URL(string: "mongofold://node?path=\(encoded)")
        return str
    }

    private func makePlaceholderLink(path: String, text: String) -> AttributedString {
        var str = AttributedString(text)
        str.foregroundColor = .secondary
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        str.link = URL(string: "mongofold://node?path=\(encoded)")
        return str
    }

    private func styled(_ text: String, color: Color) -> AttributedString {
        var str = AttributedString(text)
        str.foregroundColor = color
        return str
    }

    private func escapeJSONString(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{8}": result += "\\b"
            case "\u{c}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.append(Character(scalar))
                }
            }
        }
        return result
    }
}
