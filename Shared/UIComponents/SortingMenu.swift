
import SwiftUI

struct SortingMenu<T: SortOption>: View where T: Hashable, T: CaseIterable {
    @Binding var selectedOption: T
    @Binding var ascending: Bool
    
    var body: some View {
        Menu {
            Section("Sort By") {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Button {
                        if selectedOption == option {
                            ascending.toggle()
                        } else {
                            selectedOption = option
                            ascending = true
                        }
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if selectedOption == option {
                                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.yellow)
        }
    }
}

protocol SortOption: CaseIterable, Hashable {
    var displayName: String { get }
}

