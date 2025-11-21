# Communally iOS App

🎉 **Project Status: READY FOR XCODE** 🎉

Communally is an iOS app that connects people locally — those offering help (jobs or volunteering) with those seeking opportunities. It uses Google authentication, personalized onboarding flows for job seekers (13+) and job hirers (18+), and a simple dashboard showing real, nearby opportunities using location data.

## 🚀 Quick Start

**Open the project in Xcode:**
```bash
open Communally.xcodeproj
```

Or see **START_HERE.md** for detailed instructions.

## Features

- **Google Sign-In Authentication**: Fast, secure login with Google
- **Dual User Types**: Job Seekers (13+) and Job Hirers (18+)
- **Personalized Onboarding**: Age-appropriate flows with parental approval for teens
- **Location-Based Opportunities**: Find nearby jobs and volunteer work
- **Interactive Map**: Visual representation of opportunities
- **Messaging System**: Communicate with matched users
- **Beautiful UI**: Light lime green and white theme with gradient backgrounds

## Setup Instructions

### ✅ Already Configured!

This project is **100% ready for Xcode**. All setup is complete:

- ✅ **Firebase SDK** - FirebaseCore & FirebaseFirestore configured
- ✅ **Google Sign-In SDK** - OAuth and URL schemes set up
- ✅ **GoogleService-Info.plist** - Firebase configuration included
- ✅ **Bundle ID** - `shaurlabs.Communally`
- ✅ **Development Team** - Code signing configured
- ✅ **Permissions** - Location services declared
- ✅ **Info.plist** - All required keys configured

### Installation (30 seconds)

1. **Open in Xcode**:
   ```bash
   open Communally.xcodeproj
   ```

2. **Wait for Package Resolution**:
   - Xcode will automatically download Firebase & Google Sign-In
   - Takes 1-2 minutes on first open

3. **Select Device**:
   - Choose iPhone simulator or connected device

4. **Build and Run**:
   - Press `⌘+R` to build and run
   - That's it!

## Project Structure

```
Communally/
├── Models/
│   └── User.swift                 # User and data models
├── Services/
│   ├── AuthenticationManager.swift # Google Sign-In handling
│   └── LocationManager.swift      # Location services
├── Views/
│   ├── AuthenticationView.swift   # Sign-in screen
│   ├── OnboardingView.swift        # User onboarding flow
│   ├── DashboardView.swift        # Main app dashboard
│   └── MessagingView.swift        # Chat functionality
├── Theme/
│   └── Theme.swift                # App styling and colors
├── CommunallyApp.swift           # Main app entry point
└── ContentView.swift             # Root view controller
```

## User Flows

### Job Seekers (13+)
1. **Google Sign-In** → Authentication
2. **Profile Creation** → Name, age, profile picture
3. **Parental Approval** → Required for users under 18
4. **Skills Selection** → Choose relevant skills
5. **Description** → Age-appropriate options
6. **Dashboard** → Browse opportunities

### Job Hirers (18+)
1. **Google Sign-In** → Authentication
2. **Profile Creation** → Name, age, profile picture
3. **Skills Selection** → Choose relevant skills
4. **Description** → Professional options
5. **Location Setup** → Optional location sharing
6. **Dashboard** → Post and manage opportunities

## Key Components

### AuthenticationManager
- Handles Google Sign-In integration
- Manages user session state
- Provides user profile data

### LocationManager
- Requests location permissions
- Provides current location data
- Searches for nearby opportunities

### Theme System
- Consistent light lime green and white design
- Gradient backgrounds
- Rounded corners and shadows
- Typography hierarchy

## Dependencies

- **GoogleSignIn**: For authentication
- **SwiftUI**: For UI framework
- **MapKit**: For map functionality
- **CoreLocation**: For location services

## Future Enhancements

- Backend API integration
- Push notifications
- Real-time messaging
- Payment processing
- Advanced filtering
- User reviews and ratings
- Social features

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
