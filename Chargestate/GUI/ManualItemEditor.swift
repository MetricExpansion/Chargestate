//
//  ManualItemEditor.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/12/21.
//

import SwiftUI

struct ManualItemEditor: View {
    @State var date: Date
    @Binding var showing: Bool
    let saveAction: (Date) -> ()
    var body: some View {
        List {
            Label("Ensure vehicle is fully charged by: ", systemImage: "bolt.fill")
                .accentColor(.green)
                .listRowSeparator(.hidden)
            VStack {
                DatePicker(
                     selection: $date,
                     displayedComponents: [.date, .hourAndMinute]
                ) {
                }
            }
        }
        .listStyle(.automatic)
        
        .datePickerStyle(.graphical)
        .navigationTitle("Editing")
        .navigationBarItems(leading: Button(action: {
            showing = false
        }) {
            Text("Cancel")
        }, trailing: Button(action: {
            saveAction(date)
            showing = false
        }) {
            Text("Done").bold()
        })

    }
}

struct ManualItemEditor_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ManualItemEditor(date: Date(), showing: .constant(true)) { date in
                
            }
        }
    }
}
