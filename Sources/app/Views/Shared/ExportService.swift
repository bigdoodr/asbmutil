import SwiftUI
import UniformTypeIdentifiers
import ASBMUtilCore

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case tsv = "TSV"
    case plist = "Property List"
    case serials = "Serial Numbers"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .tsv: return "tsv"
        case .plist: return "plist"
        case .serials: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .tsv: return .tabSeparatedText
        case .plist: return .propertyList
        case .serials: return .plainText
        }
    }

    var icon: String {
        switch self {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .tsv: return "tablecells.badge.ellipsis"
        case .plist: return "doc.text"
        case .serials: return "list.number"
        }
    }
}

enum ExportService {
    @MainActor static func export(devices: [DeviceAttributes], format: ExportFormat) {
        let content = generate(devices: devices, format: format)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "devices.\(format.fileExtension)"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor static func copyToClipboard(devices: [DeviceAttributes], format: ExportFormat) {
        let content = generate(devices: devices, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    static func generate(devices: [DeviceAttributes], format: ExportFormat) -> String {
        switch format {
        case .csv: return generateCSV(devices)
        case .json: return generateJSON(devices)
        case .tsv: return generateTSV(devices)
        case .plist: return generatePlist(devices)
        case .serials: return devices.map(\.serialNumber).joined(separator: "\n")
        }
    }

    private static let columns = [
        "Serial Number", "Model", "Product Family", "Product Type", "Status",
        "Storage", "Color", "Source", "Order Number", "Part Number",
        "Order Date", "Added", "Updated"
    ]

    private static func values(for d: DeviceAttributes) -> [String] {
        [d.serialNumber, d.displayModel, d.productFamily ?? "", d.productType ?? "",
         d.status ?? "", d.deviceCapacity ?? "", d.color ?? "",
         d.purchaseSourceType ?? "", d.orderNumber ?? "", d.partNumber ?? "",
         d.orderDateTime ?? "", d.addedToOrgDateTime ?? "", d.updatedDateTime ?? ""]
    }

    private static func generateCSV(_ devices: [DeviceAttributes]) -> String {
        var out = columns.joined(separator: ",") + "\n"
        for d in devices {
            out += values(for: d).map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }
        return out
    }

    private static func generateTSV(_ devices: [DeviceAttributes]) -> String {
        var out = columns.joined(separator: "\t") + "\n"
        for d in devices {
            out += values(for: d).joined(separator: "\t") + "\n"
        }
        return out
    }

    private static func generateJSON(_ devices: [DeviceAttributes]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(devices),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func generatePlist(_ devices: [DeviceAttributes]) -> String {
        let dicts: [[String: String]] = devices.map { d in
            Dictionary(uniqueKeysWithValues: zip(columns, values(for: d)))
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dicts, format: .xml, options: 0
        ), let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    // MARK: - AppleCare+ export (DeviceInfo)

    /// Flat-format columns (CSV/TSV/Plist) include only AppleCare+ coverage — never Limited
    /// Warranty or any other coverage type a device may also carry, per TDX's requirements.
    /// JSON keeps full fidelity (all coverage types) since it uses DeviceInfo's own Codable
    /// representation, matching what `asbmutil get-devices-info`/`list-devices
    /// --include-applecare` already produce on the CLI side.
    private static let appleCarePlusColumns = [
        "AppleCare+ Status", "AppleCare+ Agreement #", "AppleCare+ Start", "AppleCare+ End", "AppleCare+ Renewable"
    ]

    private static func appleCarePlusValues(for info: DeviceInfo) -> [String] {
        guard let plan = info.appleCarePlus else { return ["", "", "", "", ""] }
        return [
            plan.status ?? "", plan.agreementNumber ?? "",
            plan.startDateTime ?? "", plan.endDateTime ?? "",
            plan.isRenewable == true ? "Yes" : "No"
        ]
    }

    @MainActor static func export(devices: [DeviceInfo], format: ExportFormat) {
        let content = generate(devices: devices, format: format)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "devices-applecare.\(format.fileExtension)"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor static func copyToClipboard(devices: [DeviceInfo], format: ExportFormat) {
        let content = generate(devices: devices, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    static func generate(devices: [DeviceInfo], format: ExportFormat) -> String {
        switch format {
        case .csv: return generateCSV(devices)
        case .json: return generateJSON(devices)
        case .tsv: return generateTSV(devices)
        case .plist: return generatePlist(devices)
        case .serials: return devices.map(\.device.serialNumber).joined(separator: "\n")
        }
    }

    private static func generateCSV(_ devices: [DeviceInfo]) -> String {
        let cols = columns + appleCarePlusColumns
        var out = cols.joined(separator: ",") + "\n"
        for info in devices {
            let row = values(for: info.device) + appleCarePlusValues(for: info)
            out += row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }
        return out
    }

    private static func generateTSV(_ devices: [DeviceInfo]) -> String {
        let cols = columns + appleCarePlusColumns
        var out = cols.joined(separator: "\t") + "\n"
        for info in devices {
            let row = values(for: info.device) + appleCarePlusValues(for: info)
            out += row.joined(separator: "\t") + "\n"
        }
        return out
    }

    private static func generateJSON(_ devices: [DeviceInfo]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(devices),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func generatePlist(_ devices: [DeviceInfo]) -> String {
        let cols = columns + appleCarePlusColumns
        let dicts: [[String: String]] = devices.map { info in
            Dictionary(uniqueKeysWithValues: zip(cols, values(for: info.device) + appleCarePlusValues(for: info)))
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dicts, format: .xml, options: 0
        ), let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}
