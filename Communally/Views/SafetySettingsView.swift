//
//  SafetySettingsView.swift
//  Communally
//
//  Configure emergency contacts and safety preferences
//

import SwiftUI

struct SafetySettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var emergencyContacts: [EmergencyContact] = []
    @State private var showingAddContact = false
    @State private var enableFallDetection = true
    @State private var enableOvertimeAlerts = true
    @State private var enableMovementTracking = true
    @State private var checkInInterval: TimeInterval = 1800 // 30 minutes
    
    var body: some View {
        NavigationView {
            Form {
                // Safety Monitoring Section
                Section {
                    Toggle("Fall Detection", isOn: $enableFallDetection)
                    Toggle("Overtime Alerts", isOn: $enableOvertimeAlerts)
                    Toggle("Movement Tracking", isOn: $enableMovementTracking)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check-In Frequency")
                            .font(.system(size: 16, weight: .medium))
                        
                        Picker("Interval", selection: $checkInInterval) {
                            Text("Every 15 min").tag(TimeInterval(900))
                            Text("Every 30 min").tag(TimeInterval(1800))
                            Text("Every hour").tag(TimeInterval(3600))
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Label("Safety Monitoring", systemImage: "shield.checkered")
                }
                
                // Emergency Contacts Section
                Section {
                    if emergencyContacts.isEmpty {
                        Text("No emergency contacts added")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(emergencyContacts) { contact in
                            EmergencyContactRow(contact: contact)
                        }
                        .onDelete(perform: deleteContact)
                    }
                    
                    Button(action: {
                        showingAddContact = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            Text("Add Emergency Contact")
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                    }
                } header: {
                    Label("Emergency Contacts", systemImage: "person.fill.badge.plus")
                } footer: {
                    Text("These contacts will be notified if you don't respond to a safety check-in.")
                }
                
                // Information Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(
                            icon: "location.fill",
                            title: "GPS Tracking",
                            description: "Monitors unusual location changes"
                        )
                        
                        InfoRow(
                            icon: "figure.fall",
                            title: "Fall Detection",
                            description: "Detects sudden impacts via accelerometer"
                        )
                        
                        InfoRow(
                            icon: "clock.fill",
                            title: "Overtime Alerts",
                            description: "Checks in if job runs longer than expected"
                        )
                        
                        InfoRow(
                            icon: "bell.badge.fill",
                            title: "Auto Check-Ins",
                            description: "Regular safety confirmations during jobs"
                        )
                    }
                } header: {
                    Label("How It Works", systemImage: "info.circle")
                }
            }
            .navigationTitle("Safety Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddEmergencyContactView(contacts: $emergencyContacts)
            }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "emergencyContacts_\(authManager.currentUser?.id ?? "")"),
           let contacts = try? JSONDecoder().decode([EmergencyContact].self, from: data) {
            emergencyContacts = contacts
        }
        
        enableFallDetection = UserDefaults.standard.bool(forKey: "enableFallDetection")
        enableOvertimeAlerts = UserDefaults.standard.bool(forKey: "enableOvertimeAlerts")
        enableMovementTracking = UserDefaults.standard.bool(forKey: "enableMovementTracking")
        checkInInterval = UserDefaults.standard.double(forKey: "checkInInterval")
        
        // Set defaults if not set
        if checkInInterval == 0 {
            checkInInterval = 1800
        }
    }
    
    private func saveSettings() {
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(emergencyContacts) {
            UserDefaults.standard.set(encoded, forKey: "emergencyContacts_\(authManager.currentUser?.id ?? "")")
        }
        
        UserDefaults.standard.set(enableFallDetection, forKey: "enableFallDetection")
        UserDefaults.standard.set(enableOvertimeAlerts, forKey: "enableOvertimeAlerts")
        UserDefaults.standard.set(enableMovementTracking, forKey: "enableMovementTracking")
        UserDefaults.standard.set(checkInInterval, forKey: "checkInInterval")
        
        print("✅ Safety settings saved")
    }
    
    private func deleteContact(at offsets: IndexSet) {
        emergencyContacts.remove(atOffsets: offsets)
    }
}

// MARK: - Emergency Contact Model

struct EmergencyContact: Identifiable, Codable {
    let id: String
    let name: String
    let phoneNumber: String
    let relationship: String
    
    init(id: String = UUID().uuidString, name: String, phoneNumber: String, relationship: String) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.relationship = relationship
    }
}

// MARK: - Supporting Views

struct EmergencyContactRow: View {
    let contact: EmergencyContact
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
            
            HStack(spacing: 12) {
                Text(contact.relationship)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Text("•")
                    .foregroundColor(.gray)
                
                Text(contact.phoneNumber)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddEmergencyContactView: View {
    @Binding var contacts: [EmergencyContact]
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var relationship = "Parent"
    
    private let relationships = ["Parent", "Sibling", "Friend", "Spouse", "Other"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Contact Information") {
                    TextField("Name", text: $name)
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel).tag(rel)
                        }
                    }
                }
            }
            .navigationTitle("Add Emergency Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(name.isEmpty || phoneNumber.isEmpty)
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveContact() {
        let contact = EmergencyContact(
            name: name,
            phoneNumber: phoneNumber,
            relationship: relationship
        )
        contacts.append(contact)
        dismiss()
    }
}

#Preview {
    SafetySettingsView()
        .environmentObject(AuthenticationManager.shared)
}
