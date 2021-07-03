//
//  AnimatedEllipses.swift
//  Chargestate
//
//  Created by Avinash Vakil on 7/2/21.
//

import SwiftUI

struct AnimatedEllipses: View {
    var loadingColor: Color = .blue
    var finishedColor: Color = .green
    @ObservedObject var loading: StateManager
    @State private var xPos: CGFloat = 0.0
    @State private var barWidth: CGFloat = 0.5
    @State private var gradOpacity: CGFloat = 0.0
    @State private var solidOpacity: CGFloat = 0.0
    @State private var animation: Animation = .default
    var showButton: Bool = false
    
    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    Rectangle()
                        .fill(LinearGradient(colors: [loadingColor.opacity(0.0) ,loadingColor, loadingColor.opacity(0.0)], startPoint: .leading, endPoint: .trailing))
                        .opacity(gradOpacity)
                    Rectangle()
                        .foregroundColor(finishedColor)
                        .opacity(solidOpacity)
                }
                .animation(animation, value: xPos)
                .animation(animation, value: barWidth)
                .animation(animation, value: gradOpacity)
                .animation(animation, value: solidOpacity)
                .frame(width: geo.size.width * barWidth)
                .position(x: barWidth(viewWidth: geo.size.width), y: geo.size.height / 2)
                .onAppear {
                    handleStateChange(loading.loading)
                }
                .onChange(of: loading.loading) { v in
                    handleStateChange(loading.loading)
                }
            }
            if showButton {
                Button(action: {
                    switch loading.loading {
                    case .loading:
                        loading.setCompleted()
                    case .idle:
                        loading.setStarted()
                    case .finished:
                        loading.setStarted()
                    }
                }) {
                    Text("Change")
                }
            }
        }
    }
    
    func barWidth(viewWidth: CGFloat) -> CGFloat {
        return (viewWidth + 2 * (viewWidth * barWidth)) * xPos - (viewWidth * barWidth)
    }
    
    func handleStateChange(_ state: AnimatedEllipsesState) {
        switch state {
        case .loading:
            animation = Animation.linear(duration: 0.0)
            withAnimation {
                xPos = 0.0
                barWidth = 0.3
                gradOpacity = 1.0
                solidOpacity = 0.0
            }
            animation = Animation.easeInOut(duration: 0.77).repeatForever(autoreverses: false)
            withAnimation {
                xPos = 1.0
            }
        case .idle:
            animation = Animation.linear(duration: 1.0)
            withAnimation {
                xPos = 0.5
                barWidth = 1.0
                gradOpacity = 0.0
                solidOpacity = 0.0

            }
        case .finished:
            animation = Animation.easeOut(duration: 2.0)
            withAnimation {
                xPos = 0.5
            }
            animation = Animation.easeOut(duration: 0.15)
            withAnimation {
                // xPos = 0.5
                barWidth = 1.0
                gradOpacity = 0.0
                solidOpacity = 1.0
            }
        }

    }
}

class StateManager: ObservableObject {
    @Published var loading: AnimatedEllipsesState = .idle
    
    func setCompleted() {
        switch loading {
        case .loading:
            loading = .finished
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                self?.loading = .idle
            }
            return
        case .idle:
            return
        case .finished:
            return
        }
    }
    
    func setStarted() {
        switch loading {
        case .loading:
            return
        case .idle:
            loading = .loading
        case .finished:
            return
        }
    }
}

enum AnimatedEllipsesState {
    case idle
    case loading
    case finished
}

struct AnimatedEllipses_Previews: PreviewProvider {
    static var previews: some View {
        AnimatedEllipses(loading: StateManager(), showButton: true)
            .previewLayout(.fixed(width: 300, height: 30))
    }
}
