"""
Test award pricing fetch for a few destinations before running full batch.
"""

import pandas as pd
import subprocess
import sys

# Read spreadsheet
df = pd.read_excel('CLT_Trips_With_Real_Prices.xlsx')

# Test with just first 3 destinations
test_df = df.head(3).copy()

# Save test file
test_df.to_excel('CLT_Trips_Test.xlsx', index=False)

print("Created test file with 3 destinations:")
print(test_df[['Destination', 'City', 'Depart CLT', 'Depart Destination']].to_string())

print("\n" + "="*60)
print("To run the test:")
print("  python fetch_award_pricing.py")
print("\nThis will take ~5-10 minutes for 3 destinations (6 flight searches)")
print("="*60)
