//
//  ContentView.swift
//  stream
//
//  Created by Caspian Zhao on 2024/1/29.
//

import SwiftUI
import AVKit
import Foundation
import AVFoundation
import Combine

struct VoiceSettings: Codable {
    let stability: Double
    let similarityBoost: Double
}

struct Message: Codable {
    let text: String
    let voiceSettings: VoiceSettings?
    let xiApiKey: String?
    let tryTriggerGeneration: Bool?
    
    enum CodingKeys: String, CodingKey {
        case text
        case voiceSettings = "voice_settings"
        case xiApiKey = "xi_api_key"
        case tryTriggerGeneration = "try_trigger_generation"
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    private var isAudioPlayerReady = true
    
    @Published var isPlaying = false
    
    func appendAudioData(_ data: Data) {
        if data.isEmpty {
           print("Received empty audio data, skipping.")
           return
       }

        print("Appending audio data of size: \(data.count) bytes")

        // 将音频数据添加到队列中
        audioQueue.append(data)
        
        // 如果音频播放器准备好了，就播放队列中的第一个音频数据
        if isAudioPlayerReady {
            playNextAudioData()
        }
    }
    
    private func playNextAudioData() {
        // 确保队列中有数据
        guard !audioQueue.isEmpty else {
            print("Audio queue is empty, no data to play.")
            return
        }
        
        // 获取队列中的第一个音频数据
        let audioData = audioQueue.removeFirst()
        print("Playing audio data of size: \(audioData.count) bytes")
        
        do {
            // 创建音频播放器
            audioPlayer = try AVAudioPlayer(data: audioData)
            print("Audio player created successfully.")
            
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            print("Audio player prepared to play.")
            
            audioPlayer?.play()
            print("Audio player started playing.")
            
            isPlaying = true
            isAudioPlayerReady = false // 设置为不准备好状态，防止重复播放
        } catch {
            print("Error creating audio player: \(error.localizedDescription)")
            if let audioPlayerError = error as? NSError {
                print("Error code: \(audioPlayerError.code), domain: \(audioPlayerError.domain)")
            }
            isPlaying = false
            isAudioPlayerReady = true // 出错时重置状态，以便进行下一次尝试
        }
    }

    
    func stopAudio() {
        // 停止音频播放器，并清空队列
        audioPlayer?.stop()
        audioQueue.removeAll()
        isPlaying = false
        isAudioPlayerReady = true
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if !audioQueue.isEmpty {
            playNextAudioData()
        } else {
            isPlaying = false
            isAudioPlayerReady = true
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(String(describing: error))")
        isPlaying = false
        isAudioPlayerReady = true
    }
}


struct ContentView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var isConnected = false
    private let urlSession = URLSession(configuration: .default)
    
    @State private var audioBuffer = Data()
    @State private var player_v2: AVPlayer?
    
    @State private var isLooping = false;
    
    @State private var inputText = ""
    @State private var nextWords = ""
    @State private var timer: Timer? = nil
    
    @ObservedObject var audioPlayerManager = AudioPlayerManager()

    var body: some View {
        VStack {
//            Button(action: togglePlayPause) {
//                Image(systemName: isPlaying ? "pause.circle" : "play.circle")
//                    .font(.largeTitle)
//            }
//            Button("重置") {
//                resetAudio()
//            }
//            .padding()
            TextField("Enter your text here", text: $inputText)
                           .textFieldStyle(RoundedBorderTextFieldStyle())
                           .padding()
            // Add a new button to manually connect to WebSocket
            Button(self.isLooping ? "Connect WebSocket" : "Disconnect WebSocket") {
               setupTimer()
           }
           .padding()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .padding()
    }
    
    private func setupTimer() {
        self.isLooping = true;
        
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if !inputText.isEmpty {
                nextWords = inputText
                inputText = ""
                
                print(nextWords)
                connectToWebSocket()
            } else {
                timer?.invalidate()
                timer = nil
                self.isLooping = false
                print("No new input, stopping the timer.")
            }
        }
    }
    
    private func connectToWebSocket() {
        let voiceId = "OiPxMr8b7mL9wBqR0S9n"
        let model = "eleven_turbo_v2"
        let apiKey = ""
        // Construct WebSocket URL
        let wsURLString = "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream-input?model_id=\(model)"
        let webSocketURL = URL(string: wsURLString)!
              
        webSocketTask = urlSession.webSocketTask(with: webSocketURL)
        webSocketTask?.resume()
        listenToWebSocket()
        
        self.isConnected = true
        print("Connected! Waiting for send message...")
        
        sendMessage(Message(
            text: " ",
            voiceSettings: VoiceSettings(stability: 0.5, similarityBoost: 0.8),
            xiApiKey: apiKey,
            tryTriggerGeneration: nil
        ))
        
//        for _ in 1...3 {
//            sendMessage(Message(
//                text: "Hello World",
//                voiceSettings: nil,
//                xiApiKey: nil,
//                tryTriggerGeneration: true
//            ))
//            Thread.sleep(forTimeInterval: 5.0)
//        }
        sendMessage(Message(
            text: "\(nextWords) ",
            voiceSettings: nil,
            xiApiKey: nil,
            tryTriggerGeneration: true
        ))
        
        sendMessage(Message(
            text: "",
            voiceSettings: nil,
            xiApiKey: nil,
            tryTriggerGeneration: nil
        ))
    }
    
    private func sendMessage(_ messageObject: Message) {
        guard let webSocketTask = webSocketTask else {
            return
        }
        
        let encoder = JSONEncoder()
        if let messageData = try? encoder.encode(messageObject),
           let messageString = String(data: messageData, encoding: .utf8) {
            print("Sending message: \(messageString)")
            // Use your existing logic to send the message as string
            let message = URLSessionWebSocketTask.Message.string(messageString)
            print(message)
            webSocketTask.send(message) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                }
            }
        } else {
            print("Failed to encode message")
        }
    }
    
    private func listenToWebSocket() {
        webSocketTask?.receive { result in
            switch result {
            case .failure(let error):
                // Handle the WebSocket connection failure and log the error
                print("WebSocket connection failed: \(error)")
                disconnectWebSocket()
                
            case .success(let message):
                switch message {
                case .string(let text):
                    print("Received string: \(text)")
                    
                    if let data = text.data(using: .utf8) {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                if let alignment = json["alignment"] as? [String: Any],
                                   let normalizedAlignment = json["normalizedAlignment"] as? [String: Any],
                                   !alignment.isEmpty,
                                   !normalizedAlignment.isEmpty {
                                    
                                    if let audioBase64 = json["audio"] as? String, !audioBase64.isEmpty {
                                        if let audioData = Data(base64Encoded: audioBase64) {
                                            print("Audio data received and decoded.")
                                            // 如果 alignment 和 normalizedAlignment 有值，追加音频数据到AudioPlayerManager的缓冲区
                                            self.audioPlayerManager.appendAudioData(audioData)
                                        } else {
                                            print("Error: Unable to decode Base64 audio string.")
                                        }
                                    }
                                } else {
                                    print("Alignment data is missing or incomplete.")
                                }
                                
                                if let isFinal = json["isFinal"] as? Bool, isFinal {
                                    print("isFinal is true, closing the WebSocket.")
                                    disconnectWebSocket()
                                    return
                                }
                            }
                        } catch {
                            print("Error parsing JSON: \(error)")
                        }
                    }
                    
                default:
                    break
                }
                
                // Keep listening
                self.listenToWebSocket()
            }
        }
    }
    
    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.isConnected = false
        print("WebSocket disconnected")
    }

    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            fetchAudioData()
        }
    }

    private func fetchAudioData() {
        // Define the POST request parameters
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/OiPxMr8b7mL9wBqR0S9n/stream")!
        let apiKey = ""
        let requestData: [String: Any] = [
            "text": "Hello ",
            "model_id": "eleven_turbo_v2",
            "voice_settings": [
                "similarity_boost": 0.5,
                "stability": 0.5
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            print("Error encoding request data: \(error)")
            return
        }

        // Perform the POST request
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data {
                do {
                    // Create a temporary file and write the data to it
                    let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    let tempFileURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
                    try data.write(to: tempFileURL, options: .atomic)
                    
                    // Create AVAsset from the temporary file
                    let asset = AVAsset(url: tempFileURL)
                    let playerItem = AVPlayerItem(asset: asset)
                    
                    DispatchQueue.main.async {
                        self.player = AVPlayer(playerItem: playerItem)
                        self.player?.play()
                        self.isPlaying = true
                    }
                } catch {
                    print("Error saving data to temporary file: \(error)")
                }
            } else if let error = error {
                print("Error fetching audio URL: \(error)")
            }
        }.resume()
    }

    private func resetAudio() {
        player?.pause()
        isPlaying = false
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
