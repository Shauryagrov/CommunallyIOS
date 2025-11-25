# Smart Rating System Documentation

## Overview

The Communally app now includes a comprehensive 5-star rating system that allows job hirers to rate job seekers after completing work. The system includes **smart candidate ranking** that automatically sorts applicants by their likelihood of being a good match based on multiple factors.

## Key Features

### ⭐ 5-Star Rating System

- Job hirers can rate job seekers from 1 to 5 stars after completing a job
- Optional text reviews for detailed feedback
- Rating history tracked for each user
- Detailed rating breakdown showing distribution of 1-5 star ratings

### 🆕 Fair Start for New Users

- **New job seekers start with 4.0 stars** to give them a fair chance
- Job hirers can clearly see when someone is new with a "New" badge
- Informative message explaining the 4-star starting rating
- Rating updates as they complete more jobs

### 🎯 Smart Candidate Ranking

The system automatically ranks applicants using a sophisticated scoring algorithm based on:

1. **Rating Score (50 points max)**
   - Based on average rating out of 5 stars
   - New users start with 4.0 stars (40 points)

2. **Experience (20 points max)**
   - More completed jobs = higher score
   - 2 points per completed job, capped at 20

3. **Reliability (15 points max)**
   - Based on percentage of 5-star ratings
   - Shows consistent quality of work

4. **Recency (10 points max)**
   - Recent applicants get slight boost
   - Rewards active job seekers

5. **Competitiveness (5 points max)**
   - Reserved for future price-based ranking

**Total Score: 0-100 points**

### 🏆 Ranking Badges

Top applicants receive visual badges:
- **Top Match** 👑 - Best candidate (green badge)
- **Great Match** ⭐ - Second best (blue badge)  
- **Good Match** ✓ - Third best (orange badge)

## User Interface

### For Job Hirers

#### 1. **Viewing Applicants**

When viewing applicants for a job:
- Applicants are **automatically sorted by best match**
- Top matches are clearly marked with colored badges
- Each applicant shows:
  - Rating (e.g., "4.0 ⭐")
  - Number of previous ratings (e.g., "(5)")
  - "New" badge for first-time users
- Smart ranking info banner explains the sorting

#### 2. **Rating After Job Completion**

When a hirer marks a job as complete:
1. Job is marked as completed
2. Rating sheet automatically appears
3. Hirer can:
   - Select 1-5 stars (tap to select)
   - See live rating description (Excellent, Very Good, Good, Fair, Poor)
   - Optionally add written review (max 500 characters)
   - Submit rating

### For Job Seekers

#### Viewing Their Ratings

Job seekers can see their rating stats showing:
- **Overall Rating** (e.g., "4.5 out of 5")
- **Total Number of Ratings**
- **Star Distribution Bar Chart**
  - Shows percentage for each star level (1-5 stars)
- **For New Users**:
  - Shows 4.0 stars with "New user • Starting rating" badge
  - Info message explaining the fair start system

## Technical Implementation

### Models

#### Rating Model
```swift
struct Rating {
    let opportunityId: String
    let applicationId: String
    let raterId: String          // Hirer
    let ratedUserId: String      // Job Seeker
    let score: Double            // 1.0 - 5.0
    let review: String?          // Optional text
    let createdAt: Date
    let jobTitle: String
}
```

#### UserRatingStats
```swift
struct UserRatingStats {
    let userId: String
    var totalRatings: Int
    var averageScore: Double     // 4.0 for new users
    var fiveStarCount: Int
    var fourStarCount: Int
    var threeStarCount: Int
    var twoStarCount: Int
    var oneStarCount: Int
}
```

### Services

#### RatingManager
- Manages all rating operations
- Calculates user statistics
- Implements smart ranking algorithm
- Syncs with Firebase Firestore
- Sends notifications for new ratings

### Views

#### RateUserView
- Modal sheet for submitting ratings
- Interactive star selection
- Optional review text field
- Success confirmation

#### UserRatingDisplay
- Two modes: `compact` and `full`
- Compact: Shows rating and count inline
- Full: Shows detailed breakdown with bar charts
- Automatically handles new users

#### RatingBadge
- Visual badges for top matches
- Color-coded by rank
- Crown icon for top match

## Firebase Structure

### Collections

#### `ratings` Collection
```javascript
{
  opportunityId: "opportunity123",
  applicationId: "app456",
  raterId: "hirer789",
  raterName: "John Smith",
  ratedUserId: "seeker101",
  ratedUserName: "Jane Doe",
  score: 5.0,
  review: "Excellent work!",
  createdAt: Timestamp,
  jobTitle: "Garden Maintenance"
}
```

#### `userStats` Collection
```javascript
{
  userId: "seeker101",
  totalRatings: 12,
  averageScore: 4.7,
  fiveStarCount: 10,
  fourStarCount: 2,
  threeStarCount: 0,
  twoStarCount: 0,
  oneStarCount: 0,
  lastUpdated: Timestamp
}
```

### Security Rules

Add these rules to your `firestore.rules`:

```javascript
// Rating rules
match /ratings/{ratingId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null && 
                   request.resource.data.raterId == request.auth.uid;
  allow update, delete: if false; // Ratings cannot be edited or deleted
}

// User stats rules
match /userStats/{userId} {
  allow read: if request.auth != null;
  allow write: if false; // Only server-side updates
}
```

## Usage Examples

### How Rankings Work

**Example Scenario:** 3 applicants for a gardening job:

1. **Sarah** (Top Match 👑)
   - Rating: 4.8/5.0 (12 ratings)
   - 10 five-star ratings
   - Applied 2 hours ago
   - **Score: 88.5 points**

2. **Mike** (Great Match ⭐)
   - Rating: 4.2/5.0 (6 ratings)
   - 3 five-star ratings  
   - Applied 5 hours ago
   - **Score: 74.2 points**

3. **Alex** (Good Match ✓)
   - Rating: 4.0/5.0 (0 ratings - NEW!)
   - Starting rating
   - Applied 1 day ago
   - **Score: 70.0 points**

### Why New Users Get 4 Stars

- **Fair Chance**: New users aren't penalized for being new
- **Trust Builder**: Shows they're trustworthy until proven otherwise
- **Competitive**: Keeps them competitive with experienced workers
- **Transparent**: Job hirers know it's a starting rating
- **Dynamic**: Rating updates with real feedback

## Best Practices

### For Job Hirers

1. **Review all applicants** - Smart ranking helps, but review everyone
2. **Read full profiles** - Don't rely solely on ratings
3. **Check "New" badges** - Consider giving new users a chance
4. **Rate fairly** - Your ratings help the community
5. **Leave reviews** - Written feedback is valuable

### For Job Seekers

1. **Do quality work** - Good ratings lead to more opportunities
2. **Be professional** - Ratings reflect your reliability
3. **Complete jobs** - More completed jobs = better ranking
4. **Start strong** - First ratings set your trajectory
5. **Build reputation** - Consistent good work builds trust

## Future Enhancements

Potential additions to the rating system:

1. **Mutual Ratings**: Let job seekers rate job hirers
2. **Verified Badges**: Special badges for verified users
3. **Skill-Based Ratings**: Rate specific skills separately
4. **Response Time**: Factor in how quickly they respond
5. **Completion Rate**: Track job completion percentage
6. **Price Comparison**: Include pricing in smart ranking
7. **Location Proximity**: Boost local applicants
8. **Repeat Customers**: Bonus for working together before

## Troubleshooting

### Common Issues

**Q: New user shows 0 stars instead of 4**
**A:** Check that `getStats(forUser:)` returns 4.0 as default average

**Q: Rankings seem wrong**
**A:** Verify all components of the ranking algorithm are calculated correctly

**Q: Rating sheet doesn't appear after completion**
**A:** Check that `acceptedJobSeeker` is properly loaded in `onAppear`

**Q: "New" badge doesn't show**
**A:** Ensure `stats.hasRatings` is false for new users

## Summary

The smart rating system provides:
- ✅ Fair 5-star ratings
- ✅ 4-star starting rating for new users
- ✅ Transparent "New" user indicators
- ✅ Smart algorithmic ranking (0-100 points)
- ✅ Visual ranking badges
- ✅ Detailed rating statistics
- ✅ Automatic sorting by best match
- ✅ Optional written reviews
- ✅ Firebase integration
- ✅ Real-time updates

This creates a fair, transparent, and efficient system for matching job hirers with the best candidates!

