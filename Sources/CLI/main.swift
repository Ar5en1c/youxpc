// main.swift - YouxPC v2 CLI entry point
//
// Thin CLI:
//   youxpc mcp       Start the MCP server (used by Claude Code)
//   youxpc setup     Interactive setup wizard
//   youxpc doctor    Diagnose issues and suggest fixes
//   youxpc status    Quick health check
//   youxpc receipts  Show the log of what agents did
//   youxpc version   Print version

import AppKit
import ApplicationServices
import Foundation
import YouxPC

// Force CoreGraphics server connection initialization.
// ScreenCaptureKit requires a CG connection to the window server.
_ = CGMainDisplayID()

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"

switch command {
case "mcp":
    let server = MCPServer()
    server.run()

case "setup":
    let wizard = SetupWizard()
    wizard.run()

case "doctor":
    var doctor = Doctor()
    doctor.run()

case "status":
    printStatus()

case "receipts":
    ReceiptsCommand().run(Array(args.dropFirst()))

case "version", "--version", "-v":
    print("YouxPC v\(Product.version)")

case "help", "--help", "-h":
    printUsage()

default:
    fputs("Unknown command: \(command)\n", stderr)
    printUsage()
    exit(1)
}

// MARK: - Status

func printStatus() {
    print("YouxPC v\(Product.version)")
    print("")

    let hasAX = AXIsProcessTrusted()
    print("Accessibility: \(hasAX ? "granted" : "NOT GRANTED")")
    if !hasAX {
        print("  Run: youxpc setup")
    }

    let hasScreenRecording = ScreenCapture.hasPermission()
    print("Screen Recording: \(hasScreenRecording ? "granted" : "not granted")")

    let recipes = RecipeStore.listRecipes()
    print("Recipes: \(recipes.count) installed")

    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    print("Running apps: \(apps.count)")

    print("")
    print(hasAX ? "Status: Ready" : "Status: Run `youxpc setup` first")
}

// MARK: - Usage

func printUsage() {
    print("""
    YouxPC v\(Product.version) - Accessibility-tree MCP server for AI agents

    Usage: youxpc <command>

    Commands:
      mcp       Start the MCP server (used by Claude Code)
      setup     Interactive setup wizard (first-time configuration)
      doctor    Diagnose issues and suggest fixes
      status    Quick health check
      receipts  Show what agents did (--last N, --today, --run ID, --summary, --json)
      version   Print version

    Get started:
      youxpc setup     Configure permissions and MCP
      youxpc doctor    Check if everything is working

    YouxPC gives AI agents eyes and hands on macOS.
    """)
}
