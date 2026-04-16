//
//  PopoverContentView.swift
//  SCU Network Helper
//
//  Created by Terminal Void on 2026/3/15.
//

import SwiftUI

struct PopoverContentView: View {
    // === 状态变量 ===
    @StateObject private var networkManager = NetworkManager.shared
    
    // === 用户配置 (自动保存) ===
    // 读取 AppStorage 中的账号密码
    @AppStorage("username") private var username = ""
    @AppStorage("serviceName") private var serviceName = "EDUNET"
    @AppStorage("isAutoLoginEnabled") private var isAutoLoginEnabled = false
    // 网卡绑定配置
    @AppStorage("loginInterface") private var loginInterface = "en0"
    @AppStorage("detectInterface") private var detectInterface = "en0"
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. 顶部状态与操作区
            VStack(spacing: 12) {
                HStack {
                    Text("当前状态:")
                        .foregroundColor(.secondary)
                    Spacer()
                    // 动态颜色显示状态
                    Text(networkManager.connectionStatus)
                        .font(.headline)
                        .foregroundColor((networkManager.connectionStatus == "登录成功" || networkManager.connectionStatus == "已在线" || networkManager.connectionStatus == "休眠" || networkManager.connectionStatus == "一般Wi-Fi") ? .green : .orange)
                }
                
                Button(action: {
                    Task {
                        let securePassword = KeychainHelper.standard.readPassword() ?? ""
                        if securePassword.isEmpty {
                            networkManager.connectionStatus = "请先在设置中保存密码"
                            return
                        }
                        // 🌟 这里多加了一个 interface 参数
                        await networkManager.login(userId: username, pass: securePassword, service: serviceName, interface: loginInterface)
                    }
                }) {
                    Text(networkManager.isLoggingIn ? "正在请求..." : "手动登录")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(networkManager.isLoggingIn || username.isEmpty)
            }
            
            Divider()
            
            // 2. 核心设置区
            VStack(alignment: .leading, spacing: 12) {
                Picker("运营商", selection: $serviceName) {
                    Text("校园网 (EDUNET)").tag("EDUNET")
                    Text("中国电信").tag("CHINATELECOM")
                    Text("中国移动").tag("CHINAMOBILE")
                    Text("中国联通").tag("CHINAUNICOM")
                }
                
                Toggle("开启断网自动重连", isOn: $isAutoLoginEnabled)
            }
            
            Divider()
            
            // 3. 高级网卡设置区
            VStack(alignment: .leading, spacing: 12) {
                Text("高级设置 (指定网卡)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("检测网卡")
                    Spacer()
                    TextField("如 en0", text: $detectInterface)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                HStack {
                    Text("登录网卡")
                    Spacer()
                    TextField("如 en8", text: $loginInterface)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            
            Divider()
            
            // 4. 底部工具栏
            HStack {
                Button("退出程序") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                
                Spacer()
                
                // 这里可以放一个前往系统偏好设置输入密码的入口，或者齿轮图标
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        // 限制面板宽度，保持紧凑美观
        .frame(width: 280)
    }
    
    
}

//#Preview {
//    PopoverContentView()
//}
