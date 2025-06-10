#!/usr/bin/env python3

"""
Quick Copilot Data Explorer
===========================
Interactive tool to explore your Copilot data.
"""

import pandas as pd
import sys
from pathlib import Path

def explore_data(data_file):
    """Interactive data exploration."""
    
    if not Path(data_file).exists():
        print(f"❌ Data file not found: {data_file}")
        return
    
    # Load data
    df = pd.read_csv(data_file)
    df['hitdttm'] = pd.to_datetime(df['hitdttm'])
    
    print("🔍 COPILOT DATA EXPLORER")
    print("=" * 50)
    print(f"📁 Data file: {data_file}")
    print(f"📊 Total records: {len(df):,}")
    print(f"📅 Date range: {df['hitdttm'].min()} to {df['hitdttm'].max()}")
    print("")
    
    while True:
        print("\n🔍 What would you like to explore?")
        print("1. 👥 View all users and their activity")
        print("2. 💻 View programming languages used")
        print("3. 🔧 View Copilot features used")
        print("4. ⏰ View activity by hour")
        print("5. 📊 View detailed statistics")
        print("6. 🔍 Search and filter data")
        print("7. 📋 Export filtered data")
        print("8. 🚪 Exit")
        
        choice = input("\nEnter your choice (1-8): ").strip()
        
        if choice == '1':
            print("\n👥 USER ACTIVITY:")
            user_stats = df.groupby('user_login').agg({
                'hitdttm': ['count', 'min', 'max'],
                'language': lambda x: ', '.join(x.unique()[:3])
            })
            user_stats.columns = ['interactions', 'first_use', 'last_use', 'languages']
            print(user_stats.to_string())
            
        elif choice == '2':
            print("\n💻 PROGRAMMING LANGUAGES:")
            lang_stats = df['language'].value_counts()
            for lang, count in lang_stats.items():
                percentage = (count / len(df)) * 100
                print(f"{lang}: {count} interactions ({percentage:.1f}%)")
                
        elif choice == '3':
            print("\n🔧 COPILOT FEATURES:")
            if 'label' in df.columns:
                feature_stats = df['label'].value_counts()
                for feature, count in feature_stats.items():
                    percentage = (count / len(df)) * 100
                    print(f"{feature}: {count} interactions ({percentage:.1f}%)")
            else:
                print("No feature data available")
                
        elif choice == '4':
            print("\n⏰ ACTIVITY BY HOUR:")
            if 'hour' in df.columns:
                hourly = df['hour'].value_counts().sort_index()
                for hour, count in hourly.items():
                    bar = "█" * (count // max(1, max(hourly) // 20))
                    print(f"{hour:2d}:00 - {count:2d} interactions {bar}")
            else:
                df['hour'] = df['hitdttm'].dt.hour
                hourly = df['hour'].value_counts().sort_index()
                for hour, count in hourly.items():
                    print(f"{hour:2d}:00 - {count} interactions")
                    
        elif choice == '5':
            print("\n📊 DETAILED STATISTICS:")
            print(f"Columns: {', '.join(df.columns)}")
            print(f"Data types:")
            print(df.dtypes.to_string())
            print(f"\nSample data:")
            print(df.head(3).to_string())
            
        elif choice == '6':
            print("\n🔍 SEARCH AND FILTER:")
            print("Available columns:", ', '.join(df.columns))
            column = input("Enter column name to filter by: ").strip()
            if column in df.columns:
                unique_values = df[column].unique()[:10]
                print(f"Sample values: {', '.join(map(str, unique_values))}")
                value = input("Enter value to filter by: ").strip()
                filtered = df[df[column].astype(str).str.contains(value, case=False, na=False)]
                print(f"\n📊 Found {len(filtered)} matching records:")
                if len(filtered) > 0:
                    print(filtered[['user_login', 'hitdttm', 'language', 'label']].to_string())
            else:
                print("Column not found")
                
        elif choice == '7':
            print("\n📋 EXPORT OPTIONS:")
            export_name = input("Enter filename (without .csv): ").strip()
            if export_name:
                df.to_csv(f"{export_name}.csv", index=False)
                print(f"✅ Data exported to {export_name}.csv")
                
        elif choice == '8':
            print("👋 Thanks for exploring!")
            break
            
        else:
            print("❌ Invalid choice. Please try again.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python data_explorer.py <csv_file>")
        print("Example: python data_explorer.py copilot_analysis_fabrikam_20250610_150615/data/raw_copilot_data.csv")
        sys.exit(1)
    
    explore_data(sys.argv[1])
