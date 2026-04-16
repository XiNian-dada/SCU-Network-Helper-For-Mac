//
//  NetworkManager.swift
//  SCU Network Helper
//
//  Created by Terminal Void on 2026/3/15.
//

//
//  NetworkManager.swift
//  SCU Network Helper
//

import Foundation
import Combine
import Network // 🌟 引入苹果底层网络框架，实现零功耗物理监听
import CoreWLAN
import CoreLocation

class NetworkManager: NSObject,ObservableObject,CLLocationManagerDelegate {
    static let shared = NetworkManager()
    
    @Published var connectionStatus: String = "未登录"
    @Published var isLoggingIn: Bool = false
    @Published var hasLocationPermission: Bool = false
    
    private let mainURL = "http://192.168.2.135/"
    
    // 完美复刻 Python requests 的二次表单编码 (% 替换为 %25)
    private let serviceCodes: [String: String] = [
        "CHINATELECOM": "%25E7%2594%25B5%25E4%25BF%25A1%25E5%2587%25BA%25E5%258F%25A3",
        "CHINAMOBILE": "%25E7%25A7%25BB%25E5%258A%25A8%25E5%2587%25BA%25E5%258F%25A3",
        "CHINAUNICOM": "%25E8%2581%2594%25E9%2580%259A%25E5%2587%25BA%25E5%258F%25A3",
        "EDUNET": "internet"
    ]
    
    // 🌟 自动化控制句柄
    private var networkMonitor: NWPathMonitor?
    private var pingTask: Task<Void, Never>?
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        // 设置代理
        locationManager.delegate = self
        // 1. 检查当前的权限状态
        let status = locationManager.authorizationStatus
        self.hasLocationPermission = (status == .authorized || status == .authorizedAlways)
        
        if status == .notDetermined {
            // 如果用户还没做决定（初次启动），只请求权限，不启动网络监听！
            print("🛡️ 初次启动，等待用户授予位置权限...")
            locationManager.requestAlwaysAuthorization()
        } else {
            // 如果以前已经授权过（或拒绝过），直接启动网络监听
            print("🛡️ 权限已确认，直接启动网络监听...")
            setupNativeNetworkMonitor()
        }
        
        // 2. App 启动时，直接挂载底层物理网络监听器
        setupNativeNetworkMonitor()
    }
    
    // 🌟 监听通知（Delegate 回调）：只有当权限改变时，才更新我们的变量
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // 更新缓存变量
        self.hasLocationPermission = (status == .authorized || status == .authorizedAlways)
        
        if status != .notDetermined {
            print("🛡️ 权限状态发生改变: \(status.rawValue)")
            if self.networkMonitor == nil {
                setupNativeNetworkMonitor()
            }
        }
    }
    
    // ==========================================
    // MARK: - 🤖 自动化与心跳探测引擎 (零功耗版)
    // ==========================================
    
    private func setupNativeNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        
        // 只有当网卡物理状态（插拔网线、开关Wi-Fi）发生改变时，系统才会唤醒这段代码
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let detectIf = UserDefaults.standard.string(forKey: "detectInterface") ?? "en0"
            let isAutoLoginEnabled = UserDefaults.standard.bool(forKey: "isAutoLoginEnabled")
            
            //目标SSID
            let targetSSID = UserDefaults.standard.string(forKey : "SSID") ?? "SCUNET"
            
            // 检查指定的网卡是否在活跃列表中
            let isTargetInterfaceActive = path.availableInterfaces.contains(where: { $0.name == detectIf })
            
            if isTargetInterfaceActive && path.status == .satisfied && isAutoLoginEnabled {
                
                print("🔌 [物理层] 网卡 \(detectIf) 已连通")
                // 🧐 逻辑判断：
                // 如果是 Wi-Fi 网络，必须匹配 "SCUNET" 才放行, 如果无法获取SSID也放行
                // 如果是 有线网络 (例如在宿舍用了扩展坞插网线)，是没有 SSID 的，直接放行
                let isWiFi = path.usesInterfaceType(.wifi)
                
                if !isWiFi {
                    print("🔌 \(detectIf) 接入有线网络，正在唤醒心跳探测引擎...")
                    DispatchQueue.main.async {
                        self.connectionStatus = "有线网络已连接"
                    }
                    self.startPingLoop()
                }
                else if self.hasLocationPermission{
                    let currentSSID = self.getCurrentSSID(interfaceName: detectIf)
                    if currentSSID == nil{
                        print("🔌 \(detectIf) 获取Wi-Fi名称失败，正在唤醒心跳探测引擎...")
                        DispatchQueue.main.async {
                            self.connectionStatus = "接入未知Wi-Fi"
                        }
                        self.startPingLoop()
                    }
                    else{
                        if currentSSID == targetSSID {
                            print("🔌 \(detectIf) 接入SCUNET，正在唤醒心跳探测引擎...")
                            DispatchQueue.main.async {
                                self.connectionStatus = "接入SCUNET"
                            }
                            self.startPingLoop()
                        }
                        else{
                            print("🔌 \(detectIf) 接入非校园网Wi-Fi")
                            DispatchQueue.main.async {
                                self.connectionStatus = "一般Wi-Fi"
                            }
                            self.stopPingLoop()
                        }
                    }
                    
                }
                else{
                    print("🔌 \(detectIf) 无位置权限，正在唤醒心跳探测引擎...")
                    DispatchQueue.main.async {
                        self.connectionStatus = "接入未知Wi-Fi"
                    }
                    self.startPingLoop()
                }
                
            } else {
                print("💤 [物理层] 网卡 \(detectIf) 已断开或未开启重连，彻底休眠，释放 CPU。")
                DispatchQueue.main.async {
                    self.connectionStatus = "休眠"
                }
                self.stopPingLoop()
            }
        }
        
        // 放入后台队列运行
        let queue = DispatchQueue(label: "SCUNetworkMonitorQueue")
        networkMonitor?.start(queue: queue)
    }
    
    private func startPingLoop() {
        if pingTask != nil { return } // 防止重复启动
        
        pingTask = Task {
            while !Task.isCancelled {
                // 每 5 秒探测一次
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                
                // 如果任务被系统掐断，或者当前正在手动登录，则跳过
                if Task.isCancelled { break }
                if self.isLoggingIn { continue }
                
                let detectIf = UserDefaults.standard.string(forKey: "detectInterface") ?? "en0"
                let loginIf = UserDefaults.standard.string(forKey: "loginInterface") ?? "en0"
                let address = UserDefaults.standard.string(forKey: "pingAddress") ?? "222.220.212.130"
                
                // 发起指定网卡的底层 Ping 探测
                let isAlive = await ping(address: address, interface: detectIf)
                
                if !isAlive {
                    print("💔 [心跳探测] 网卡 \(detectIf) 无法 Ping 通检测地址，触发自动重连！")
                    let username = UserDefaults.standard.string(forKey: "username") ?? ""
                    let service = UserDefaults.standard.string(forKey: "serviceName") ?? "EDUNET"
                    let password = KeychainHelper.standard.readPassword() ?? ""
                    
                    if !username.isEmpty && !password.isEmpty {
                        await MainActor.run { self.connectionStatus = "断网重连中..." }
                        await self.login(userId: username, pass: password, service: service, interface: loginIf)
                    }
                }
                else{
                    await MainActor.run { self.connectionStatus = "已在线" }
                }
            }
        }
    }
    
    private func stopPingLoop() {
        pingTask?.cancel() // 直接就地正法，停止 while 循环
        pingTask = nil
    }
    
    private func ping(address: String, interface: String) async -> Bool {
        return await Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = [
                "-c", "1",           // 只发 1 个包
                "-W", "2000",        // 超时时间 2000 毫秒
                "-b", interface,     // 强制绑定检测网卡
                address
            ]
            
            // 扔进黑洞，防止管道阻塞卡死
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                print("Ping \(address) via \(interface) Returned \(task.terminationStatus)")
                return task.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
    
    // ==========================================
    // MARK: - 🚀 核心登录业务逻辑 (CURL 防弹版)
    // ==========================================
    
    @MainActor
    func login(userId: String, pass: String, service: String, interface: String) async {
        self.isLoggingIn = true
        self.connectionStatus = "正在获取参数..."
        print("\n========== 🚀 [CURL模式] 开始校园网登录 ==========")
        print("🔗 绑定的物理网卡: \(interface)")
        
        do {
            // 1️⃣ 获取探测页面，拦截已在线状态
            let probeResult = try await runCurl(url: mainURL, interface: interface, postData: nil)
            if probeResult.finalURL.contains("success.jsp") || probeResult.finalURL.contains("redirectortosuccess.jsp") {
                self.connectionStatus = "已在线"
                self.isLoggingIn = false
                print("   -> ✅ 检测到设备已在线，停止请求。")
                print("========== 🏁 登录流程结束 ==========\n")
                return
            }
            
            // 2️⃣ 提取 queryString
            guard let queryString = extractQueryString(from: probeResult.body) else {
                self.connectionStatus = "未找到认证参数"
                self.isLoggingIn = false
                print("❌ 提取 queryString 失败！")
                return
            }
            
            self.connectionStatus = "正在验证..."
            
            // 3️⃣ 发送 POST 登录请求
            let loginPostURL = "\(mainURL)eportal/InterFace.do?method=login"
            let serviceCode = serviceCodes[service] ?? "internet"
            let postDataString = "userId=\(userId)&password=\(pass)&service=\(serviceCode)&queryString=\(queryString)&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false"
            
            let loginResult = try await runCurl(url: loginPostURL, interface: interface, postData: postDataString)
            
            // 4️⃣ 解析结果
            let loginResponseString = loginResult.body
            if loginResponseString.contains("\"result\":\"success\"") {
                self.connectionStatus = "登录成功"
                print("   -> 🎉 登录成功！")
            } else {
                let errorMsg = extractErrorMessage(from: loginResponseString) ?? "未知错误"
                self.connectionStatus = "失败: \(errorMsg)"
                print("   -> ❌ 登录被拒绝: \(errorMsg)")
            }
            
        } catch {
            self.connectionStatus = "命令执行异常"
            print("\n💥 [致命错误] 执行失败: \(error.localizedDescription)")
        }
        
        self.isLoggingIn = false
        print("========== 🏁 登录流程结束 ==========\n")
    }
    
    private func runCurl(url: String, interface: String, postData: String?) async throws -> (body: String, finalURL: String) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                let pipe = Pipe()
                
                // 彻底防御死锁：将错误输出扔进黑洞
                task.standardError = FileHandle.nullDevice
                
                task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                var args = [
                    "-s", "-L",
                    "--interface", interface,
                    "--connect-timeout", "3",
                    "-m", "5",
                    "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                    "-w", "\n|||%{url_effective}"
                ]
                
                if let data = postData {
                    args.append(contentsOf: ["-X", "POST", "-d", data])
                }
                
                args.append(url)
                task.arguments = args
                task.standardOutput = pipe
                
                do {
                    try task.run()
                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    
                    // 强制 UTF-8 兼容解码，无惧 ePortal 乱码刺客
                    let outputString = String(decoding: outputData, as: UTF8.self)
                    
                    if outputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(throwing: NSError(domain: "CurlError", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "网卡 \(interface) 无响应或超时断开"]))
                        return
                    }
                    
                    let components = outputString.components(separatedBy: "\n|||")
                    let body = components.first ?? ""
                    let finalURL = components.count > 1 ? components.last! : url
                    
                    continuation.resume(returning: (body, finalURL))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // ==========================================
    // MARK: - 📡 CoreWLAN 辅助方法
    // ==========================================
    
    /// 获取指定网卡的 SSID (需要关闭沙盒，并在最新的 macOS 申请位置权限)
    private func getCurrentSSID(interfaceName: String) -> String? {
        // 使用 CWWiFiClient 获取特定名称（如 en0）的网卡接口，并读取 SSID
        if let interface = CWWiFiClient.shared().interface(withName: interfaceName) {
            return interface.ssid()
        }
        return nil
    }
    
    
    
    // ==========================================
    // MARK: - ✂️ 辅助文本解析方法
    // ==========================================
    
    private func extractQueryString(from html: String) -> String? {
        let parts = html.components(separatedBy: "/index.jsp?")
        if parts.count > 1 {
            let finalParts = parts[1].components(separatedBy: "'</script>")
            if finalParts.count > 0 {
                let rawQuery = finalParts[0]
                var allowedCharacters = CharacterSet.urlQueryAllowed
                allowedCharacters.remove(charactersIn: "!*'();:@&=+$,/?%#[]")
                return rawQuery.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? rawQuery
            }
        }
        return nil
    }
    
    private func extractErrorMessage(from jsonStr: String) -> String? {
        let parts = jsonStr.components(separatedBy: "\"message\":\"")
        if parts.count > 1 {
            let finalParts = parts[1].components(separatedBy: "\",\"")
            if finalParts.count > 0 {
                return decodeUnicode(finalParts[0])
            }
        }
        return nil
    }
    
    private func decodeUnicode(_ string: String) -> String {
        guard let data = "\"\(string)\"".data(using: .utf8) else { return string }
        do {
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            return string
        }
    }
}
