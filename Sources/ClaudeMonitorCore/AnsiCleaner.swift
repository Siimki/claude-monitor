import Foundation

/// Replays the small VT100 subset used by Claude Code and returns the visible screen.
public enum AnsiCleaner {
    public static func clean(_ input: String, rows: Int = 50, columns: Int = 100) -> String {
        var terminal = Terminal(rows: rows, columns: columns)
        terminal.consume(Array(input.unicodeScalars))
        return terminal.rendered
    }
}

private struct Terminal {
    let rows: Int
    let columns: Int
    var screen: [[Character]]
    var row = 0
    var column = 0
    var savedRow = 0
    var savedColumn = 0

    init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        screen = Array(repeating: Array(repeating: " ", count: columns), count: rows)
    }

    mutating func consume(_ scalars: [Unicode.Scalar]) {
        var i = 0
        while i < scalars.count {
            let value = scalars[i].value
            if value == 0x1B {
                i = consumeEscape(scalars, from: i)
            } else {
                consumeVisible(scalars[i])
            }
            i += 1
        }
    }

    var rendered: String {
        screen.map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private mutating func consumeEscape(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        guard start + 1 < scalars.count else { return start }
        let next = scalars[start + 1].value
        if next == 0x5B { // CSI: ESC [ ... final byte
            var end = start + 2
            while end < scalars.count {
                let byte = scalars[end].value
                if (0x40...0x7E).contains(byte) { break }
                end += 1
            }
            guard end < scalars.count else { return scalars.count - 1 }
            let body = String(String.UnicodeScalarView(scalars[(start + 2)..<end]))
            handleCSI(body: body, command: scalars[end])
            return end
        }
        if next == 0x5D { // OSC: terminate with BEL or ST
            return skipStringEscape(scalars, from: start + 2, allowsBell: true)
        }
        if next == 0x50 || next == 0x5E || next == 0x5F { // DCS, PM, APC
            return skipStringEscape(scalars, from: start + 2, allowsBell: false)
        }
        if (0x20...0x2F).contains(next) { // Character-set and other ESC intermediates
            var end = start + 2
            while end < scalars.count, !(0x30...0x7E).contains(scalars[end].value) { end += 1 }
            return min(end, scalars.count - 1)
        }
        switch next {
        case 0x37: savedRow = row; savedColumn = column
        case 0x38: row = savedRow; column = savedColumn
        case 0x44: lineFeed()
        case 0x45: lineFeed(); column = 0
        case 0x4D:
            if row > 0 { row -= 1 }
        default: break
        }
        return start + 1
    }

    private func skipStringEscape(_ scalars: [Unicode.Scalar], from start: Int,
                                  allowsBell: Bool) -> Int {
        var i = start
        while i < scalars.count {
            if allowsBell, scalars[i].value == 0x07 { return i }
            if scalars[i].value == 0x1B, i + 1 < scalars.count,
               scalars[i + 1].value == 0x5C { return i + 1 }
            i += 1
        }
        return scalars.count - 1
    }

    private mutating func consumeVisible(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x00, 0x07: break
        case 0x08: column = max(0, column - 1)
        case 0x09: column = min(columns - 1, ((column / 8) + 1) * 8)
        case 0x0A, 0x0B, 0x0C: lineFeed()
        case 0x0D: column = 0
        case 0x20...0x10FFFF:
            if column >= columns { column = 0; lineFeed() }
            screen[row][column] = Character(String(scalar))
            column += 1
        default: break
        }
    }

    private mutating func lineFeed() {
        row += 1
        if row >= rows {
            screen.removeFirst()
            screen.append(Array(repeating: " ", count: columns))
            row = rows - 1
        }
    }

    private mutating func handleCSI(body: String, command: Unicode.Scalar) {
        let numeric = body.trimmingCharacters(in: CharacterSet(charactersIn: "?<=>!"))
        let values = numeric.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) }
        func parameter(_ index: Int, default defaultValue: Int = 1) -> Int {
            guard index < values.count, let value = values[index], value != 0 else { return defaultValue }
            return value
        }

        switch command.value {
        case 0x41: row = max(0, row - parameter(0)) // A
        case 0x42: row = min(rows - 1, row + parameter(0)) // B
        case 0x43: column = min(columns - 1, column + parameter(0)) // C
        case 0x44: column = max(0, column - parameter(0)) // D
        case 0x45: row = min(rows - 1, row + parameter(0)); column = 0 // E
        case 0x46: row = max(0, row - parameter(0)); column = 0 // F
        case 0x47: column = min(columns - 1, max(0, parameter(0) - 1)) // G
        case 0x48, 0x66: // H, f
            row = min(rows - 1, max(0, parameter(0) - 1))
            column = min(columns - 1, max(0, parameter(1) - 1))
        case 0x64: row = min(rows - 1, max(0, parameter(0) - 1)) // d
        case 0x4A: eraseDisplay(mode: values.first.flatMap { $0 }) // J
        case 0x4B: eraseLine(mode: values.first.flatMap { $0 }) // K
        case 0x50: deleteCharacters(parameter(0)) // P
        case 0x58: eraseCharacters(parameter(0)) // X
        case 0x40: insertCharacters(parameter(0)) // @
        case 0x53: scrollUp(parameter(0)) // S
        case 0x54: scrollDown(parameter(0)) // T
        case 0x73: savedRow = row; savedColumn = column // s
        case 0x75: row = savedRow; column = savedColumn // u
        default: break // styles, modes, device queries, scroll regions
        }
    }

    private mutating func eraseDisplay(mode: Int?) {
        switch mode ?? 0 {
        case 2, 3:
            screen = Array(repeating: Array(repeating: " ", count: columns), count: rows)
        case 1:
            for r in 0...row {
                let end = r == row ? column : columns - 1
                if end >= 0 { for c in 0...end { screen[r][c] = " " } }
            }
        default:
            for r in row..<rows {
                let start = r == row ? column : 0
                if start < columns { for c in start..<columns { screen[r][c] = " " } }
            }
        }
    }

    private mutating func eraseLine(mode: Int?) {
        switch mode ?? 0 {
        case 1:
            for c in 0...min(column, columns - 1) { screen[row][c] = " " }
        case 2:
            screen[row] = Array(repeating: " ", count: columns)
        default:
            if column < columns { for c in column..<columns { screen[row][c] = " " } }
        }
    }

    private mutating func eraseCharacters(_ count: Int) {
        for c in column..<min(columns, column + count) { screen[row][c] = " " }
    }

    private mutating func deleteCharacters(_ count: Int) {
        let n = min(count, columns - column)
        screen[row].removeSubrange(column..<(column + n))
        screen[row].append(contentsOf: repeatElement(" ", count: n))
    }

    private mutating func insertCharacters(_ count: Int) {
        let n = min(count, columns - column)
        screen[row].insert(contentsOf: repeatElement(" ", count: n), at: column)
        screen[row].removeLast(n)
    }

    private mutating func scrollUp(_ count: Int) {
        for _ in 0..<min(count, rows) {
            screen.removeFirst()
            screen.append(Array(repeating: " ", count: columns))
        }
    }

    private mutating func scrollDown(_ count: Int) {
        for _ in 0..<min(count, rows) {
            screen.removeLast()
            screen.insert(Array(repeating: " ", count: columns), at: 0)
        }
    }
}
