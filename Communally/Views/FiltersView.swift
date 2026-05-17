//
//  FiltersView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI

struct FiltersView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedRadius: Double = 10
    @State private var selectedSkills: Set<String> = []
    @State private var isRemoteOnly = false
    
    private var availableSkills: [String] { OpportunityCategory.allTitles }
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Radius Filter
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distance: \(Int(selectedRadius)) miles")
                                .font(CommunallyTheme.subtitleFont)
                                .fontWeight(.semibold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Slider(value: $selectedRadius, in: 1...50, step: 1)
                                .accentColor(CommunallyTheme.primaryGreen)
                            
                            HStack {
                                Text("1 mi")
                                    .font(.caption)
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                                
                                Spacer()
                                
                                Text("50 mi")
                                    .font(.caption)
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                            }
                        }
                        
                        // Skills Filter
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Skills")
                                .font(CommunallyTheme.subtitleFont)
                                .fontWeight(.semibold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                ForEach(availableSkills, id: \.self) { skill in
                                    Button(action: {
                                        if selectedSkills.contains(skill) {
                                            selectedSkills.remove(skill)
                                        } else {
                                            selectedSkills.insert(skill)
                                        }
                                    }) {
                                        Text(skill)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(selectedSkills.contains(skill) ? .white : CommunallyTheme.darkGray)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                selectedSkills.contains(skill) ?
                                                AnyView(CommunallyTheme.buttonGradient) :
                                                AnyView(Color.white)
                                            )
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedSkills.contains(skill) ? Color.clear : CommunallyTheme.lightGray, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Additional Filters
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Additional Filters")
                                .font(CommunallyTheme.subtitleFont)
                                .fontWeight(.semibold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            VStack(spacing: 12) {
                                Toggle("Remote work only", isOn: $isRemoteOnly)
                                    .toggleStyle(SwitchToggleStyle(tint: CommunallyTheme.primaryGreen))
                            }
                        }
                    }
                    .padding(CommunallyTheme.padding)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applyFilters()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func resetFilters() {
        selectedRadius = 10
        selectedSkills.removeAll()
        isRemoteOnly = false
    }
    
    private func applyFilters() {
        // Apply filters logic here
        dismiss()
    }
}

#Preview {
    FiltersView()
}
