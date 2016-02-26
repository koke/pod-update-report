//
//  main.swift
//  pod-update-report
//
//  Created by Jorge Bernal Ordovas on 26/02/16.
//  Copyright © 2016 Automattic. All rights reserved.
//

import Foundation

struct PodUpdate {
    let name: String
    let currentVersion: String
    let availableVersion: String
    let releasesURL: NSURL?
}

enum Error: ErrorType {
    case InvalidPodUpdateOutput
    case PodDoesntHaveGitUrl
    case InvalidGithubURL
}

func runPodOutdated(path: String) -> String {
    let response = Script.run("pod", arguments: ["outdated", "--project-directory=\(path)"])
    return response.standardOutput
}

func parsePodOutdated(output: String) throws -> [PodUpdate] {
    return try output
        .componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet()) // Split into lines
        .filter({ $0.hasPrefix("-") }) // Available updates start with "-"
        .map({ line in
            let separators = NSCharacterSet(charactersInString: " ()")
            let comps = line.componentsSeparatedByCharactersInSet(separators)
            guard comps.count > 8 else {
                throw Error.InvalidPodUpdateOutput
            }
            let (name, current, available) = (comps[1], comps[2], comps[8])
            let gitUrl = try? gitURLForPod(name)
            let gitHubProject = try gitUrl.flatMap({ try gitHubProjectWithGitURL($0) })

            let releasesURL = gitHubProject.map({ gitHubReleasesURLForProject($0) })
            return PodUpdate(name: name, currentVersion: current, availableVersion: available, releasesURL: releasesURL)
        })
}

func outdatedPods(path: String) throws -> [PodUpdate] {
    return try parsePodOutdated(runPodOutdated(path))
}

func mockOutdatedPods() throws -> [PodUpdate] {
    let output = "- 1PasswordExtension 1.6.4 -> 1.6.4 (latest version 1.8)\n"
    + "- AFNetworking 2.6.3 -> 2.6.3 (latest version 3.0.4)\n"
    + "- AMPopTip 0.10.1 -> 0.10.2 (latest version 0.10.2)\n"
    return try parsePodOutdated(output)
}

func gitURLForPod(pod: String) throws -> NSURL {
    guard let searchURL = NSURL(string: "http://search.cocoapods.org/api/v1/pods.flat.hash.json?query=\(pod)&amount=1") else {
        throw Error.PodDoesntHaveGitUrl
    }
    let semaphore = dispatch_semaphore_create(0)
    var responseData: NSData? = nil
    let task = NSURLSession.sharedSession().dataTaskWithURL(searchURL) { (data, response, error) -> Void in
        responseData = data
        dispatch_semaphore_signal(semaphore)
    }
    task.resume()
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    guard let data = responseData else {
        throw Error.PodDoesntHaveGitUrl
    }
    let json = try NSJSONSerialization.JSONObjectWithData(data, options: [])
    guard let results = json as? [AnyObject],
        let result = results.first as? [String: AnyObject],
        let source = result["source"] as? [String: AnyObject],
        let git = source["git"] as? String
        else {
            throw Error.PodDoesntHaveGitUrl
    }
    guard let gitURL = NSURL(string: git) else {
        throw Error.PodDoesntHaveGitUrl
    }
    return gitURL
}

extension String {
    func stringByRemovingInitialSlash() -> String {
        if self.hasPrefix("/") {
            return String(self.characters.dropFirst(1))
        } else {
            return self
        }
    }
}

func gitHubProjectWithGitURL(gitURL: NSURL) throws -> String? {
    guard gitURL.host == "github.com" else {
        return nil
    }
    guard let gitHubURL = gitURL.URLByDeletingPathExtension,
        let gitHubPath = gitHubURL.path else {
        throw Error.InvalidGithubURL
    }
    return gitHubPath.stringByRemovingInitialSlash()
}

func gitHubReleasesURLForProject(project: String) -> NSURL {
    return NSURL(string: "https://github.com/\(project)/releases/")!
}

func printUpdate(update: PodUpdate) {
    let releaseMessage = update.releasesURL?.absoluteString ?? "Not on GitHub"
    print("\(update.name) [\(update.currentVersion) -> \(update.availableVersion)] \(releaseMessage)")
}

func printUpdates(updates: [PodUpdate]) {
    updates.forEach {
        printUpdate($0)
    }
}

//printUpdates(try mockOutdatedPods()); exit(0)
//printUpdates(try outdatedPods("~/automattic/wordpress-ios")); exit(0)

if Process.arguments.count > 2 {
    let command = Process.arguments[0]
    print("Usage: \(command) [path]")
    exit(1)
}

var path = "."
if Process.arguments.count == 2 {
    path = Process.arguments[1]
}
printUpdates(try outdatedPods(path))
