//
//  StreamingManager.swift
//  TrueDepthStreamer
//
//  Created by Nick Hageman on 5/22/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import MultipeerConnectivity
import CoreVideo
import Foundation
import UIKit

// MARK: - Streaming Manager for iPhone (Sender)
class StreamingManager: NSObject {
    private let serviceType = "depth-stream"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    
    private var session: MCSession
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser
    
    override init() {
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                          discoveryInfo: nil,
                                                          serviceType: serviceType)
        super.init()
        
        session.delegate = self
        nearbyServiceAdvertiser.delegate = self
        
        print("🟡 StreamingManager initialized with peer: \(myPeerID.displayName)")
    }
    
    func startAdvertising() {
        nearbyServiceAdvertiser.startAdvertisingPeer()
        print("🟢 Started advertising for connections with service type: \(serviceType)")
        print("🟢 Device name: \(UIDevice.current.name)")
        print("🟢 Peer ID: \(myPeerID.displayName)")
    }
    
    func stopAdvertising() {
        nearbyServiceAdvertiser.stopAdvertisingPeer()
        print("🔴 Stopped advertising")
    }
    
    // Send RGB and Depth data
    func sendFrameData(rgbPixelBuffer: CVPixelBuffer, depthPixelBuffer: CVPixelBuffer) {
        guard !session.connectedPeers.isEmpty else {
            print("⚠️ No connected peers to send data to")
            return
        }
        
        do {
            // Convert pixel buffers to data
            let rgbData = try pixelBufferToData(rgbPixelBuffer)
            let depthData = try pixelBufferToData(depthPixelBuffer)
            
            // Create frame packet
            let framePacket = FramePacket(
                timestamp: CFAbsoluteTimeGetCurrent(),
                rgbData: rgbData,
                depthData: depthData,
                rgbWidth: CVPixelBufferGetWidth(rgbPixelBuffer),
                rgbHeight: CVPixelBufferGetHeight(rgbPixelBuffer),
                depthWidth: CVPixelBufferGetWidth(depthPixelBuffer),
                depthHeight: CVPixelBufferGetHeight(depthPixelBuffer)
            )
            
            let encodedData = try JSONEncoder().encode(framePacket)
            
            try session.send(encodedData, toPeers: session.connectedPeers, with: .unreliable)
            
            print("📤 Sent frame data: RGB(\(framePacket.rgbWidth)x\(framePacket.rgbHeight)), Depth(\(framePacket.depthWidth)x\(framePacket.depthHeight)), Size: \(encodedData.count) bytes")
            
        } catch {
            print("❌ Error sending frame data: \(error)")
        }
    }
    
    private func pixelBufferToData(_ pixelBuffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let dataSize = bytesPerRow * height
        
        return Data(bytes: baseAddress, count: dataSize)
    }
}

// MARK: - MCSession Delegate
extension StreamingManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ CONNECTED to peer: \(peerID.displayName)")
                print("✅ Total connected peers: \(session.connectedPeers.count)")
            case .connecting:
                print("🔄 CONNECTING to peer: \(peerID.displayName)")
            case .notConnected:
                print("❌ DISCONNECTED from peer: \(peerID.displayName)")
                print("❌ Remaining connected peers: \(session.connectedPeers.count)")
            @unknown default:
                print("❓ Unknown connection state for peer: \(peerID.displayName)")
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📥 Received data from \(peerID.displayName) (shouldn't happen on sender)")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream,
                withName streamName: String, fromPeer peerID: MCPeerID) {
        print("📥 Received stream from \(peerID.displayName): \(streamName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                fromPeer peerID: MCPeerID, with progress: Progress) {
        print("📥 Started receiving resource from \(peerID.displayName): \(resourceName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("📥 Finished receiving resource from \(peerID.displayName): \(resourceName)")
        if let error = error {
            print("❌ Resource receive error: \(error)")
        }
    }
}

// MARK: - MCNearbyServiceAdvertiser Delegate
extension StreamingManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                   didNotStartAdvertisingPeer error: Error) {
        print("❌ FAILED to start advertising: \(error.localizedDescription)")
        print("❌ Error details: \(error)")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                   didReceiveInvitationFromPeer peerID: MCPeerID,
                   withContext context: Data?,
                   invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📨 RECEIVED INVITATION from peer: \(peerID.displayName)")
        print("📨 Context data: \(context?.count ?? 0) bytes")
        
        // Auto-accept connections from Vision Pro
        print("✅ ACCEPTING invitation from: \(peerID.displayName)")
        invitationHandler(true, session)
    }
}

// MARK: - Data Structures
struct FramePacket: Codable {
    let timestamp: CFAbsoluteTime
    let rgbData: Data
    let depthData: Data
    let rgbWidth: Int
    let rgbHeight: Int
    let depthWidth: Int
    let depthHeight: Int
}

// MARK: - Integration with your existing CameraViewController
extension CameraViewController {
    private var streamingManager: StreamingManager {
        // Add this as a property to your CameraViewController
        // private let streamingManager = StreamingManager()
        return StreamingManager() // Replace with actual property
    }
    
    func setupStreaming() {
        // Add this to your viewDidLoad
        streamingManager.startAdvertising()
        
    }
    
    // Modify your existing dataOutputSynchronizer method
    func streamFrameData(videoPixelBuffer: CVPixelBuffer, depthPixelBuffer: CVPixelBuffer) {
        // Call this from your dataOutputSynchronizer method
        streamingManager.sendFrameData(rgbPixelBuffer: videoPixelBuffer,
                                     depthPixelBuffer: depthPixelBuffer)
    }
}
