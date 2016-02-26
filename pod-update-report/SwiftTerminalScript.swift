//
//  Script.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 12/05/15.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation

/**
*   Utility class for running terminal Scripts from your Mac app.
*/
public class Script {
    
    public typealias ScriptResponse = (terminationStatus: Int, standardOutput: String, standardError: String)
    
    /**
    *   Run a script by passing in a name of the script (e.g. if you use just 'git', it will first
    *   resolve by using the 'git' at path `which git`) or the full path (such as '/usr/bin/git').
    *   Optional arguments are passed in as an array of Strings and an optional environment dictionary
    *   as a map from String to String.
    *   Back you get a 'ScriptResponse', which is a tuple around the termination status and outputs (standard and error).
    */
    public class func run(name: String, arguments: [String] = [], environment: [String: String] = [:]) -> ScriptResponse {
        
        //first resolve the name of the script to a path with `which`
        let resolved = self.runResolved("/usr/bin/which", arguments: [name], environment: [:])
        
        //which returns the path + \n, so strip the newline
        let path = resolved.standardOutput.stripTrailingNewline()
        
        //if resolving failed, just abort and propagate the failed run up
        if (resolved.terminationStatus != 0) || (path.isEmpty) {
            return resolved
        }
        
        //ok, we have a valid path, run the script
        let result = self.runResolved(path, arguments: arguments, environment: environment)
        return result
    }
    
    private class func runResolved(path: String, arguments: [String], environment: [String: String]) -> ScriptResponse {
        
        let outputPipe = NSPipe()
        let errorPipe = NSPipe()
        
        let outputFile = outputPipe.fileHandleForReading
        let errorFile = errorPipe.fileHandleForReading
        
        let task = NSTask()
        task.launchPath = path
        task.arguments = arguments
        
        var env = NSProcessInfo.processInfo().environment
        for case (_, let keyValue) in environment.enumerate() {
            env[keyValue.0] = keyValue.1
        }
        task.environment = env
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        task.launch()
        task.waitUntilExit()
        
        let terminationStatus = Int(task.terminationStatus)
        let output = self.stringFromFileAndClose(outputFile)
        let error = self.stringFromFileAndClose(errorFile)
        
        return (terminationStatus, output, error)
    }
    
    private class func stringFromFileAndClose(file: NSFileHandle) -> String {
        
        let data = file.readDataToEndOfFile()
        file.closeFile()
        let output = NSString(data: data, encoding: NSUTF8StringEncoding) as String?
        return output ?? ""
    }
}

public extension String {
    
    public func stripTrailingNewline() -> String {
        
        var stripped = self
        if stripped.hasSuffix("\n") {
            stripped.removeAtIndex(stripped.endIndex.predecessor())
        }
        return stripped
    }
}
