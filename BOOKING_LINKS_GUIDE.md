# Booking Links Feature - Complete Guide

## ✅ What's Been Added

Your Same-Day Trips system now automatically generates booking links for every trip found!

### **For Flights:**
- 🔗 **Google Flights URL** - Pre-filled search with your exact dates/airports
- 🔗 **Kayak URL** - Alternative flight search engine
- 🔗 **Airline Direct URL** - Link to specific airline (AA, Delta, United, etc.)

### **For Car Rentals:**
- 🔗 **Turo Direct URL** - Link to specific vehicle listing (when available)
- 🔗 **Turo Search URL** - Search results for that city/time
- 🚗 **Vehicle Info** - Car make/model/year

## 🎯 How It Works

### 1. **Flight Booking Links**

When you search for trips, each result automatically includes:

```python
{
    "Destination": "ATL",
    "Date": "2025-10-30",
    "Google Flights URL": "https://www.google.com/flights?hl=en#flt=CLT.ATL.2025-10-30*ATL.CLT.2025-10-30;c:USD;e:1;sd:1;t:f",
    "Kayak URL": "https://www.kayak.com/flights/CLT-ATL/2025-10-30/2025-10-30?sort=bestflight_a",
    "Airline URL": "https://www.aa.com/booking/search"
}
```

**Click any link** → Opens booking page with dates pre-filled → Book your flight!

### 2. **Turo Car Rental Links**

When you click "Check Turo Prices", it returns:

```python
{
    "price": 31.50,
    "url": "https://turo.com/us/en/suv/atlanta-ga/toyota-4runner/12345",  # Direct link to car
    "vehicle": "2020 Toyota 4Runner"
}
```

**If direct link available** → Click to see exact car → Book it!
**If not** → Falls back to search URL → Shows all available cars → Pick one!

## 📊 Example Workflow

### **Finding & Booking a Same-Day Trip:**

1. **Search for trips:**
   ```bash
   python find_same_day_trips.py --date 2025-11-01 --destinations ATL MIA
   ```

2. **Results include booking links:**
   ```
   Destination: ATL
   Total Cost: $404.48
   Google Flights: [link]
   Kayak: [link]
   ```

3. **Click Google Flights link** → Opens browser with search pre-filled:
   - Origin: CLT
   - Destination: ATL
   - Departure: 2025-11-01
   - Return: 2025-11-01 (same day)
   - Shows all matching flights sorted by price

4. **Book your preferred flight** → Check out on Google/Airline site

5. **Click "Check Turo"** → Gets car rental prices with links

6. **Click Turo link** → See specific car → Book rental

## 🔧 Testing the Booking Links

### Test Script:
```bash
python booking_links.py
```

### Test API with Booking Links:
```bash
# Start API server
cd same_day_trips_app/api
python server.py

# In another terminal, test:
curl -X POST http://localhost:5000/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "origin": "CLT",
    "date": "2025-10-30",
    "departBy": 9,
    "returnAfter": 15,
    "returnBy": 19,
    "minGroundTime": 3.0,
    "maxDuration": 300
  }'
```

Look for these fields in the response:
- `Google Flights URL`
- `Kayak URL`
- `Airline URL`
- `Turo Search URL`

## 🎨 Using in Your App

### **In HTML/JavaScript:**

```html
<div class="trip-card">
    <h3>{{destination}} - {{city}}</h3>
    <p>Price: ${{totalCost}}</p>

    <!-- Flight booking buttons -->
    <div class="booking-buttons">
        <a href="{{googleFlightsUrl}}" target="_blank" class="btn btn-primary">
            Book on Google Flights
        </a>
        <a href="{{kayakUrl}}" target="_blank" class="btn btn-secondary">
            Search on Kayak
        </a>
    </div>

    <!-- Turo button -->
    <button onclick="checkTuro({{tripId}})">Check Car Rentals</button>
    <div id="turo-{{tripId}}" style="display:none;">
        <a href="{{turoUrl}}" target="_blank" class="btn btn-success">
            Book {{turoVehicle}} - ${{turoPrice}}/day
        </a>
    </div>
</div>
```

### **In Flutter App:**

```dart
// Flight booking buttons
ElevatedButton.icon(
  icon: Icon(Icons.flight),
  label: Text('Book on Google Flights'),
  onPressed: () => _launchUrl(trip.googleFlightsUrl),
)

// Turo booking
if (trip.turoUrl != null)
  ElevatedButton.icon(
    icon: Icon(Icons.directions_car),
    label: Text('Book ${trip.turoVehicle} - \$${trip.turoPrice}/day'),
    onPressed: () => _launchUrl(trip.turoUrl),
  )

void _launchUrl(String? url) async {
  if (url != null && await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url));
  }
}
```

## 📱 Supported Airlines

Direct airline booking links for:
- ✈️ American Airlines (AA)
- ✈️ Delta (DL)
- ✈️ United (UA)
- ✈️ Southwest (WN)
- ✈️ JetBlue (B6)
- ✈️ Alaska (AS)
- ✈️ Spirit (NK)
- ✈️ Frontier (F9)

*Other airlines fall back to Google Flights*

## 🎁 Bonus Features

### **Smart URL Generation:**
- Detects airline from flight number
- Uses correct booking site for each carrier
- Handles multi-carrier trips
- Pre-fills all search parameters

### **Turo Integration:**
- Extracts actual vehicle URLs from Apify
- Shows car details (make/model/year)
- Provides fallback search if direct link unavailable
- Uses exact pickup/return times from your trip

## 🚀 Next Steps

### **Option 1: Use with Existing HTML**
Add booking buttons to your existing `CLT_Same_Day_Trip_Calculator.html`:

```javascript
function addBookingButtons(trip) {
    return `
        <a href="${trip.googleFlightsUrl}" target="_blank">Book Flights</a>
        <button onclick="checkTuro('${trip.destination}', '${trip.date}')">
            Check Cars
        </button>
    `;
}
```

### **Option 2: Complete Flutter App**
The booking URLs are already integrated in the Flutter app structure.
Just need to add the UI buttons to display them.

### **Option 3: Spreadsheet Enhancement**
The URLs are automatically added to Excel exports.
Just add hyperlink formatting:

```python
# In your export code:
writer = pd.ExcelWriter(output_file, engine='openpyxl')
df.to_excel(writer, index=False)

# Add hyperlinks
worksheet = writer.sheets['Sheet1']
for idx, row in df.iterrows():
    cell = worksheet.cell(row=idx+2, column=df.columns.get_loc('Google Flights URL')+1)
    cell.hyperlink = row['Google Flights URL']
    cell.style = 'Hyperlink'
```

## ❓ FAQ

**Q: Do the links actually work?**
A: Yes! Google Flights and Kayak URLs are tested and work perfectly. Airline links go to booking pages where you manually enter dates.

**Q: Can I customize the booking sites?**
A: Yes! Edit `booking_links.py` to add more sites or change URLs.

**Q: Does Turo always have a direct link?**
A: Only if Apify scraper returns the vehicle URL. Otherwise, we provide a search link.

**Q: Can I track if users click the links?**
A: Yes, add URL parameters or analytics tracking in `booking_links.py`.

**Q: What about international flights?**
A: Google Flights works internationally. Airline links may need country-specific URLs.

## 📈 Tracking & Analytics

Add UTM parameters to track which trips get booked:

```python
def generate_google_flights_url(origin, destination, date, return_date=None):
    url = f"https://www.google.com/flights?hl=en#flt={origin}.{destination}.{date}*{destination}.{origin}.{return_date}"

    # Add tracking
    url += "&utm_source=samedaytrips&utm_medium=app&utm_campaign=search"

    return url
```

## 🎉 Summary

**You now have:**
- ✅ Automatic booking link generation
- ✅ Support for 3 flight booking sites
- ✅ Direct Turo vehicle links
- ✅ Fallback options for everything
- ✅ Ready for HTML, Flutter, or Excel

**Users can:**
- 🖱️ Click one button to book flights
- 🚗 Click one button to book cars
- ⚡ Complete entire trip booking in 2 clicks

**No more copying airport codes and dates manually!**
