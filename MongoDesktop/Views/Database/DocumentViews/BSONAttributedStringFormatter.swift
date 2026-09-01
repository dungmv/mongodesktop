import SwiftUI
import SwiftBSON

// MARK: - BSONAttributedStringFormatter

struct BSONAttributedStringFormatter {
    var timeZone: TimeZone = .current
    var indentSpaces: Int = 2

    // Syntax Highlighting Colors
    var keyColor: Color = Color(red: 0.4, green: 0.7, blue: 1.0)
    var stringColor: Color = Color(red: 0.8, green: 0.6, blue: 0.3)
    var numberColor: Color = Color(red: 0.6, green: 0.85, blue: 0.7)
    var boolColor: Color = Color(red: 0.4, green: 0.85, blue: 0.5)
    var nullColor: Color = Color(red: 0.7, green: 0.4, blue: 0.4)
    var specialColor: Color = .orange
    var punctuationColor: Color = .secondary

    func format(document: BSONDocument) -> AttributedString {
        var output = AttributedString()
        appendDocument(document, into: &output, depth: 0)
        return output
    }

    private func appendDocument(_ doc: BSONDocument, into output: inout AttributedString, depth: Int) {
        if doc.isEmpty {
            output.append(styled("{}", color: punctuationColor))
            return
        }

        output.append(styled("{\n", color: punctuationColor))
        let indent = String(repeating: " ", count: (depth + 1) * indentSpaces)
        let closingIndent = String(repeating: " ", count: depth * indentSpaces)

        let pairs = Array(doc)
        for (idx, pair) in pairs.enumerated() {
            output.append(AttributedString(indent))
            output.append(styled("\"\(escapeJSONString(pair.key))\"", color: keyColor))
            output.append(styled(": ", color: punctuationColor))

            appendValue(pair.value, into: &output, depth: depth + 1)

            if idx < pairs.count - 1 {
                output.append(styled(",", color: punctuationColor))
            }
            output.append(AttributedString("\n"))
        }

        output.append(AttributedString(closingIndent))
        output.append(styled("}", color: punctuationColor))
    }

    private func appendArray(_ array: [BSON], into output: inout AttributedString, depth: Int) {
        if array.isEmpty {
            output.append(styled("[]", color: punctuationColor))
            return
        }

        output.append(styled("[\n", color: punctuationColor))
        let indent = String(repeating: " ", count: (depth + 1) * indentSpaces)
        let closingIndent = String(repeating: " ", count: depth * indentSpaces)

        for (idx, item) in array.enumerated() {
            output.append(AttributedString(indent))
            appendValue(item, into: &output, depth: depth + 1)

            if idx < array.count - 1 {
                output.append(styled(",", color: punctuationColor))
            }
            output.append(AttributedString("\n"))
        }

        output.append(AttributedString(closingIndent))
        output.append(styled("]", color: punctuationColor))
    }

    private func appendValue(_ value: BSON, into output: inout AttributedString, depth: Int) {
        switch value {
        case .document(let doc):
            appendDocument(doc, into: &output, depth: depth)
        case .array(let arr):
            appendArray(arr, into: &output, depth: depth)
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
            case "\u{12}": result += "\\f"
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
