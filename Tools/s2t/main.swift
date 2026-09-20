// 繁体转换工具（一次性使用，不参与 App 构建）
//
//  1. 用 macOS 内置 ICU 的 Simplified-Traditional 转换把简体逐字转成繁体
//  2. 再用术语表把「大陆用词」换成「台湾/香港用词」
//     （ICU 只转字形，不会把 设置→設定、软件→軟體、打印→列印 这类改过来）
//
// 用法: s2t <in.json> <out.json>
//   输入: {"简体原文": ["位置", ...], ...}
//   输出: {"简体原文": "繁體譯文", ...}
import Foundation

// MARK: - 术语表（键为 ICU 转换后的繁体字形，值为台湾/香港惯用词）
// 必须按长度倒序替换，否则「文件夾」会被「文件」先吃掉
let terminology: [(String, String)] = [
    // —— 系统与界面 ——
    ("屏幕錄制", "螢幕錄製"),
    ("屏幕錄影", "螢幕錄影"),
    ("屏幕", "螢幕"),
    ("顯示器", "顯示器"),
    ("多顯示器", "多螢幕"),
    ("設置", "設定"),
    ("默認", "預設"),
    ("網絡", "網路"),
    ("信息", "資訊"),
    ("鼠標", "滑鼠"),
    ("光標", "游標"),
    ("剪貼板", "剪貼簿"),
    ("文件夾", "資料夾"),
    ("文件", "檔案"),
    ("視頻", "影片"),
    ("軟件", "軟體"),
    ("硬件", "硬體"),
    ("用戶", "使用者"),
    ("支持", "支援"),
    ("粘貼", "貼上"),
    ("剪切", "剪下"),
    ("撤銷", "復原"),
    ("重做", "重做"),
    ("快捷鍵", "快速鍵"),
    ("熱鍵", "快速鍵"),
    ("全局", "全域"),
    ("另存為", "另存新檔"),
    ("按鈕", "按鈕"),
    ("工具按鈕尺寸", "工具按鈕大小"),

    // —— 功能术语 ——
    ("打印", "列印"),
    ("保存", "儲存"),
    ("標注", "標註"),
    ("對勾", "打勾"),
    ("畫筆", "筆刷"),
    ("自由畫筆", "自由筆刷"),
    ("橡皮擦", "橡皮擦"),
    ("選區坐標", "選取範圍座標"),
    ("選區", "選取範圍"),
    ("縮放", "縮放"),
    ("放大鏡", "放大鏡"),
    ("熒光筆", "螢光筆"),
    ("清空標註", "清除標註"),
    ("附加顏色", "其他顏色"),
    ("郵件發送", "郵件傳送"),
    ("發送", "傳送"),
    ("截圖文件夾", "截圖資料夾"),
    ("截圖", "截圖"),
    ("設定選區", "設定選取範圍"),
    ("啟動", "啟動"),
    ("退出程序", "結束程式"),
    ("退出", "結束"),
    ("程序", "程式"),
    ("樣式", "樣式"),
    ("外觀", "外觀"),
]

func toTraditional(_ s: String) -> String {
    let m = NSMutableString(string: s)
    CFStringTransform(m, nil, "Simplified-Traditional" as CFString, false)
    var out = m as String
    // 长词优先，避免「文件夾」被「文件」截断
    for (from, to) in terminology.sorted(by: { $0.0.count > $1.0.count }) {
        out = out.replacingOccurrences(of: from, with: to)
    }
    return out
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: s2t <in.json> <out.json>\n".data(using: .utf8)!)
    exit(2)
}
let inData = try! Data(contentsOf: URL(fileURLWithPath: args[1]))
let table = try! JSONSerialization.jsonObject(with: inData) as! [String: Any]

var out: [String: String] = [:]
for key in table.keys { out[key] = toTraditional(key) }

let outData = try! JSONSerialization.data(withJSONObject: out,
                                          options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
try! outData.write(to: URL(fileURLWithPath: args[2]))
print("转换完成: \(out.count) 条 → \(args[2])")
