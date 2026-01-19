/*
 File: AudioUtils.swift
 Description: Robust Audio Spectrum Analysis supporting BlackHole/Aggregate Devices.
*/

import Foundation
import AVFoundation
import Accelerate

class AudioSpectrumAnalyzer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private let queue = DispatchQueue(label: "com.omw.audioInput", qos: .userInteractive)
    private var isListening = false
    
    // FFT Vars
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 1024
    private var realIn: [Float] = []
    private var imagIn: [Float] = []
    private var realOut: [Float] = []
    private var imagOut: [Float] = []
    
    // Callback: Data + IsSilence
    var onSpectrumData: (([Float], Bool) -> Void)?
    
    override init() {
        super.init()
        setupFFT()
    }
    
    deinit {
        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
        stop()
    }
    
    static func getAvailableDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }
    
    func start(deviceID: String?) {
        stop()
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupSession(deviceID: deviceID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { self?.setupSession(deviceID: deviceID) }
            }
        default:
            print("Audio permission denied.")
        }
    }
    
    private func setupSession(deviceID: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            var device: AVCaptureDevice?
            if let id = deviceID, let specificDevice = AVCaptureDevice(uniqueID: id) {
                device = specificDevice
            } else {
                device = AVCaptureDevice.default(for: .audio)
            }
            
            guard let inputDevice = device else { session.commitConfiguration(); return }
            
            do {
                let input = try AVCaptureDeviceInput(device: inputDevice)
                if session.canAddInput(input) { session.addInput(input) }
                
                let output = AVCaptureAudioDataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                }
                
                session.commitConfiguration()
                session.startRunning()
                self.captureSession = session
                self.isListening = true
                print("Audio Analyzer Started: \(inputDevice.localizedName)")
            } catch {
                print("Failed to start audio session: \(error)")
            }
        }
    }
    
    func stop() {
        if isListening {
            let session = captureSession
            queue.async { session?.stopRunning() }
            captureSession = nil
            isListening = false
        }
    }
    
    private func setupFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD)
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        // Handle Audio Buffer
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr else { return }
        
        // Use AudioBufferList to handle different formats safely (Float32 vs Int16)
        // Simplified fallback: Assume Float32 usually for macOS generic inputs, handling raw bytes.
        let sampleCount = totalLength / MemoryLayout<Float>.size
        
        // Reset buffers
        memset(&realIn, 0, fftSize * MemoryLayout<Float>.size)
        
        if let ptr = dataPointer?.withMemoryRebound(to: Float.self, capacity: sampleCount) { $0 } {
            let count = min(sampleCount, fftSize)
            // Copy data. If stereo/multi-channel, this grabs interleaved data which is "okay" for visualizer visualization (mixes channels)
            for i in 0..<count {
                realIn[i] = ptr[i]
            }
        }
        
        // Perform FFT
        guard let setup = fftSetup else { return }
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        
        var spectrum = [Float](repeating: 0, count: 128)
        var totalEnergy: Float = 0
        
        // Calculate Magnitude & Normalize
        for i in 0..<128 {
            // Using a log scale or sqrt helps visualizers look better
            let real = realOut[i]
            let imag = imagOut[i]
            let mag = sqrt(real * real + imag * imag)
            
            // Boost high frequencies slightly as they are usually weaker
            let boost = 1.0 + (Float(i) / 128.0) * 0.5
            let val = min(mag / 20.0 * boost, 1.0) // Adjust sensitivity denominator if needed
            
            spectrum[i] = val
            totalEnergy += val
        }
        
        let isSilence = totalEnergy < 0.1 // Threshold for silence
        
        DispatchQueue.main.async {
            // Pass 'false' for isSimulator, forcing the engine to use THIS data even if it's zeros.
            self.onSpectrumData?(spectrum, isSilence)
        }
    }
}
