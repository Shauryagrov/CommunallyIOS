# Quick Reference - Smooth UX Components

## 🚀 Most Used Components

### Smooth Button
```swift
Button("Action") { }
    .smoothButton()
```

### Primary Button (Full Width)
```swift
Button("Continue") { }
    .buttonStyle(CommunallyTheme.primaryButtonStyle)
```

### Loading Overlay
```swift
if isLoading {
    LoadingOverlay(message: "Loading...")
}
```

### Success Overlay
```swift
if showSuccess {
    SuccessOverlay(message: "Success!") {
        dismiss()
    }
}
```

### Empty State
```swift
ProfessionalEmptyState(
    icon: "tray.fill",
    title: "Nothing Here",
    message: "Your content will appear here",
    actionTitle: "Refresh",
    action: { refresh() }
)
```

### Slide In Animation
```swift
View()
    .slideInFromBottom()
```

### Staggered List
```swift
ForEach(items.indices, id: \.self) { index in
    ItemView()
        .staggered(index: index, total: items.count)
}
```

### Toast Notification
```swift
ToastView(
    icon: "checkmark.circle.fill",
    message: "Successfully saved!",
    type: .success
)
```

### Info Card
```swift
InfoCard(
    icon: "info.circle.fill",
    title: "Tip",
    message: "New users start with 4 stars",
    color: .blue
)
```

### Card Shadow
```swift
View()
    .cardShadow()
```

## 🎯 Common Patterns

### Submit Form Flow
```swift
struct FormView: View {
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    var body: some View {
        VStack {
            // Form fields...
            
            Button("Submit") {
                submitForm()
            }
            .primaryButton(enabled: !isSubmitting)
        }
        .overlay {
            if isSubmitting {
                LoadingOverlay(message: "Submitting...")
            }
        }
        .overlay {
            if showSuccess {
                SuccessOverlay(message: "Submitted!") {
                    dismiss()
                }
            }
        }
    }
}
```

### List with Empty State
```swift
if items.isEmpty {
    ProfessionalEmptyState(...)
} else {
    ForEach(items.indices, id: \.self) { index in
        ItemCard()
            .staggered(index: index, total: items.count)
    }
}
```

## ✨ Ready to Use!

All components work out of the box. Just import and use!

