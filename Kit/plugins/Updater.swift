//
//  Updater.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 14/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import SystemConfiguration
import Security
import CryptoKit

public struct version_s {
    public let current: String
    public let latest: String
    public let newest: Bool
    public let url: String
    
    public init(current: String, latest: String, newest: Bool, url: String) {
        self.current = current
        self.latest = latest
        self.newest = newest
        self.url = url
    }
}

internal struct Version {
    var major: Int = 0
    var minor: Int = 0
    var patch: Int = 0
    
    var beta: Int? = nil
}

public class Updater {
    private let github: URL
    private let server: URL
    
    private let appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    private let currentVersion: String = "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)"
    
    private var observation: NSKeyValueObservation?
    
    private var lastCheckTS: Int {
        get {
            return Store.shared.int(key: "updater_check_ts", defaultValue: -1)
        }
        set {
            Store.shared.set(key: "updater_check_ts", value: newValue)
        }
    }
    private var lastInstallTS: Int {
        get {
            return Store.shared.int(key: "updater_install_ts", defaultValue: -1)
        }
        set {
            Store.shared.set(key: "updater_install_ts", value: newValue)
        }
    }
    
    public init(github: String, url: String) {
        self.github = URL(string: "https://api.github.com/repos/\(github)/releases/latest")!
        self.server = URL(string: "\(url)?macOS=\(ProcessInfo().operatingSystemVersion.getFullVersion())")!
    }
    
    deinit {
        observation?.invalidate()
    }
    
    public func check(force: Bool = false, completion: @escaping (_ result: version_s?, _ error: Error?) -> Void) {
        if !isConnectedToNetwork() {
            completion(nil, "No internet connection")
            return
        }
        
        let diff = (Int(Date().timeIntervalSince1970) - self.lastCheckTS) / 60
        if !force && diff <= 10 {
            completion(nil, "last check was \(diff) minutes ago, stopping...")
            return
        }
        
        defer {
            self.lastCheckTS = Int(Date().timeIntervalSince1970)
        }
        
        self.fetchRelease(uri: self.server) { (result, err) in
            guard let result = result, err == nil else {
                self.fetchRelease(uri: self.github) { (result, err) in
                    guard let result = result, err == nil else {
                        completion(nil, err)
                        return
                    }
                    
                    completion(version_s(
                        current: self.currentVersion,
                        latest: result.tag,
                        newest: isNewestVersion(currentVersion: self.currentVersion, latestVersion: result.tag),
                        url: result.url
                    ), nil)
                }
                return
            }
            
            completion(version_s(
                current: self.currentVersion,
                latest: result.tag,
                newest: isNewestVersion(currentVersion: self.currentVersion, latestVersion: result.tag),
                url: result.url
            ), nil)
        }
    }
    
    private func fetchRelease(uri: URL, completion: @escaping (_ result: (tag: String, url: String)?, _ error: Error?) -> Void) {
        let task = URLSession.shared.dataTask(with: uri) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil, "no data")
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
                guard let jsonArray = jsonResponse as? [String: Any],
                      let lastVersion = jsonArray["tag_name"] as? String,
                      let assets = jsonArray["assets"] as? [[String: Any]],
                      let asset = assets.first(where: {$0["name"] as? String == "\(self.appName).dmg"}),
                      let downloadURL = asset["browser_download_url"] as? String else {
                    completion(nil, "parse json")
                    return
                }
                
                 completion((lastVersion, downloadURL), nil)
            } catch let parsingError {
                completion(nil, parsingError)
            }
        }
        task.resume()
    }
    
    /// The release asset this download came from, so install() can fetch the
    /// checksum GitHub publishes beside it.
    private var lastDownloadURL: URL?
    
    public func download(_ url: URL, progress: @escaping (_ progress: Progress) -> Void = {_ in }, completion: @escaping (_ path: String) -> Void = {_ in }) {
        self.lastDownloadURL = url
        let downloadTask = URLSession.shared.downloadTask(with: url) { urlOrNil, _, _ in
            guard let fileURL = urlOrNil else { return }
            do {
                let downloadsURL = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let destinationURL = downloadsURL.appendingPathComponent(url.lastPathComponent)
                
                self.copyFile(from: fileURL, to: destinationURL) { (path, error) in
                    if error != nil {
                        print("copy file error: \(error ?? "copy error")")
                        return
                    }
                    
                    completion(path)
                }
            } catch {
                print("file error: \(error)")
            }
        }
        
        self.observation = downloadTask.progress.observe(\.fractionCompleted) { value, _ in
            progress(value)
        }
        
        downloadTask.resume()
    }
    
    public func install(path: String, completion: @escaping (_ error: String?) -> Void) {
        let dmg = path.replacingOccurrences(of: "file://", with: "")
        let pwd = Bundle.main.bundleURL.deletingLastPathComponent().path
        
        guard FileManager.default.fileExists(atPath: dmg) else {
            completion("DMG not found at \(dmg)")
            return
        }
        let needsElevation = !FileManager.default.isWritableFile(atPath: pwd)
        
        let diff = (Int(Date().timeIntervalSince1970) - self.lastInstallTS) / 60
        if diff <= 3 {
            completion("last install was \(diff) minutes ago, stopping...")
            return
        }
        
        print("Started new version installation...")
        
        self.verifyChecksum(of: dmg) { error in
            if let error {
                try? FileManager.default.removeItem(atPath: dmg)
                completion("DMG verification failed: \(error)")
                return
            }
            print("DMG checksum matches the published release")
            self.mountAndInstall(dmg: dmg, pwd: pwd, needsElevation: needsElevation, completion: completion)
        }
    }
    
    private func mountAndInstall(dmg: String, pwd: String, needsElevation: Bool, completion: @escaping (_ error: String?) -> Void) {
        let mountPoint: String
        do {
            mountPoint = try self.makeUniqueMountPoint()
        } catch {
            completion("failed to create mount point: \(error)")
            return
        }
        
        var attach = self.runProcess("/usr/bin/hdiutil", [
            "attach", dmg, "-mountpoint", mountPoint, "-nobrowse", "-noautoopen", "-readonly"
        ])
        if attach.exit != 0, (attach.error + attach.output).contains("is busy") {
            print("DMG is busy, remounting")
            _ = self.runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
            attach = self.runProcess("/usr/bin/hdiutil", [
                "attach", dmg, "-mountpoint", mountPoint, "-nobrowse", "-noautoopen", "-readonly"
            ])
        }
        if attach.exit != 0 {
            let msg = (attach.error + attach.output).replacingOccurrences(of: "hdiutil: attach failed - ", with: "")
            completion("Could not mount DMG (attach failed) - \(msg)")
            try? FileManager.default.removeItem(atPath: dmg)
            try? FileManager.default.removeItem(atPath: mountPoint)
            return
        }
        
        print("DMG is mounted at \(mountPoint)")
        
        let mountedApp = (mountPoint as NSString).appendingPathComponent("Perch.app")
        if let err = self.validateAppSignature(at: mountedApp) {
            _ = self.runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
            try? FileManager.default.removeItem(atPath: mountPoint)
            try? FileManager.default.removeItem(atPath: dmg)
            completion("DMG signature validation failed: \(err)")
            return
        }
        
        print("DMG signature validated")
        
        let scriptSrc = (mountedApp as NSString).appendingPathComponent("Contents/Resources/Scripts/updater.sh")
        let scriptDst = (NSTemporaryDirectory() as NSString).appendingPathComponent("stats-updater-\(UUID().uuidString).sh")
        do {
            if FileManager.default.fileExists(atPath: scriptDst) {
                try FileManager.default.removeItem(atPath: scriptDst)
            }
            try FileManager.default.copyItem(atPath: scriptSrc, toPath: scriptDst)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptDst)
        } catch {
            _ = self.runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
            completion("failed to stage updater script: \(error)")
            return
        }
        
        print("Script staged at \(scriptDst)")
        
        let scriptArgs = [scriptDst, "--app", pwd, "--dmg", dmg, "--mount", mountPoint, "--user", String(getuid())]

        if needsElevation {
            if let err = self.runElevated("/bin/bash", args: scriptArgs) {
                _ = self.runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
                try? FileManager.default.removeItem(atPath: scriptDst)
                try? FileManager.default.removeItem(atPath: mountPoint)
                completion("elevated install failed: \(err)")
                return
            }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = scriptArgs
            do {
                try task.run()
            } catch {
                completion("failed to launch updater: \(error)")
                return
            }
        }

        print("Run updater.sh with app: \(pwd) and dmg: \(dmg)")
        
        self.lastInstallTS = Int(Date().timeIntervalSince1970)
        
        exit(0)
    }
    
    private func makeUniqueMountPoint() throws -> String {
        let template = (NSTemporaryDirectory() as NSString).appendingPathComponent("Perch-update-XXXXXX")
        var bytes = Array(template.utf8).map { Int8($0) } + [Int8(0)]
        guard let dir = mkdtemp(&bytes) else {
            throw NSError(domain: "Updater", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }
        return String(cString: dir)
    }
    
    private func validateAppSignature(at path: String) -> String? {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        var status = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            return "SecStaticCodeCreateWithPath failed (\(status))"
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            return "SecStaticCodeCheckValidity failed (\(status))"
        }
        
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else {
            return "SecCodeCopySelf failed"
        }
        var selfStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic else {
            return "SecCodeCopyStaticCode failed"
        }
        // A team identifier only exists when the app is signed with a
        // Developer ID. This build is signed ad hoc, so there is nothing to
        // compare and every update failed here with "could not read current
        // team ID" -- the check could never pass, for anyone.
        //
        // Dropping it outright would leave the update unverified, so integrity
        // moves to the SHA-256 that CI publishes beside the DMG (see
        // verifyChecksum). What stays here either way is the validity check
        // above: the downloaded app must carry an intact signature.
        guard let selfTeam = self.teamID(for: selfStatic) else {
            return nil
        }
        guard let dmgTeam = self.teamID(for: code) else {
            return "could not read DMG team ID"
        }
        if selfTeam != dmgTeam {
            return "team ID mismatch: \(selfTeam) vs \(dmgTeam)"
        }
        return nil
    }
    
    /// Compares the downloaded DMG against the SHA-256 published beside it.
    ///
    /// The release workflow uploads Perch.dmg.sha256 next to every Perch.dmg,
    /// so the expected digest arrives from GitHub over TLS while the file
    /// itself is checked byte for byte. For an ad-hoc signed build this is the
    /// integrity guarantee -- without it, "update" would mean "run whatever
    /// that URL served".
    ///
    /// Fails closed: no checksum published, or no answer, means no install.
    private func verifyChecksum(of dmg: String, completion: @escaping (_ error: String?) -> Void) {
        guard let source = self.lastDownloadURL,
              let url = URL(string: source.absoluteString + ".sha256") else {
            completion("no download URL to check against")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data,
                  let code = (response as? HTTPURLResponse)?.statusCode, code == 200,
                  let text = String(data: data, encoding: .utf8),
                  let expected = text.split(separator: " ").first.map(String.init)?.lowercased(),
                  expected.count == 64 else {
                completion("could not fetch the published checksum")
                return
            }
            guard let actual = self.sha256(ofFileAt: dmg) else {
                completion("could not hash the downloaded DMG")
                return
            }
            if actual != expected {
                completion("checksum mismatch: the download does not match the published release")
                return
            }
            completion(nil)
        }.resume()
    }
    
    private func sha256(ofFileAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        
        var hasher = SHA256()
        // A megabyte at a time: the DMG is small today, and a future one should
        // not have to fit in memory to be verified.
        while true {
            guard let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    private func teamID(for code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return nil
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
    
    private func runElevated(_ tool: String, args: [String]) -> String? {
        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let authRef else {
            return "AuthorizationCreate failed (\(createStatus))"
        }
        defer { AuthorizationFree(authRef, [.destroyRights]) }

        // AuthorizationExecuteWithPrivileges is deprecated since 10.7 but still functional;
        // resolve via dlsym to avoid the compile-time deprecation warning.
        typealias AEWPFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
            return "AuthorizationExecuteWithPrivileges unavailable"
        }
        let aewp = unsafeBitCast(sym, to: AEWPFn.self)

        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        let result: OSStatus = tool.withCString { toolPtr in
            cArgs.withUnsafeMutableBufferPointer { buf in
                aewp(authRef, toolPtr, [], buf.baseAddress!, nil)
            }
        }

        if result == errAuthorizationCanceled {
            return "user canceled"
        }
        if result != errAuthorizationSuccess {
            return "AuthorizationExecuteWithPrivileges failed (\(result))"
        }
        return nil
    }

    private func runProcess(_ launch: String, _ args: [String]) -> (output: String, error: String, exit: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launch)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return ("", "runProcess: \(error.localizedDescription)", -1)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            task.terminationStatus
        )
    }
    
    private func copyFile(from: URL, to: URL, completionHandler: @escaping (_ path: String, _ error: Error?) -> Void) {
        var toPath = to
        let fileName = (URL(fileURLWithPath: to.absoluteString)).lastPathComponent
        let fileExt  = (URL(fileURLWithPath: to.absoluteString)).pathExtension
        var fileNameWithoutSuffix: String!
        var newFileName: String!
        var counter = 0
        
        if fileName.hasSuffix(fileExt) {
            fileNameWithoutSuffix = String(fileName.prefix(fileName.count - (fileExt.count+1)))
        }
        
        while toPath.checkFileExist() {
            counter += 1
            newFileName =  "\(fileNameWithoutSuffix!)-\(counter).\(fileExt)"
            toPath = to.deletingLastPathComponent().appendingPathComponent(newFileName)
        }
        
        do {
            try FileManager.default.moveItem(at: from, to: toPath)
            completionHandler(toPath.absoluteString, nil)
        } catch {
            completionHandler("", error)
        }
    }
    
    // https://stackoverflow.com/questions/30743408/check-for-internet-connection-with-swift
    private func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
    }
}
