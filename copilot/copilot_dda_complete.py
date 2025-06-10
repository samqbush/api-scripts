#!/usr/bin/env python3

"""
GitHub Copilot Direct Data Access - Complete Analysis Tool
===========================================================

This script collects Copilot usage data from GitHub's Direct Data Access API,
performs comprehensive analysis, and generates beautiful visualizations and reports.

Prerequisites:
- pip install pandas requests pyarrow matplotlib seaborn
- export GITHUB_TOKEN=your_token_here
- Token needs 'manage_billing:copilot' or 'read:enterprise' scopes
- Copilot Metrics API access policy must be enabled in enterprise settings
- Only enterprise owners and billing managers can access this data

Usage:
    python copilot_complete.py <enterprise> [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--output DIR]

Examples:
    python copilot_complete.py fabrikam
    python copilot_complete.py myenterprise --since 2025-05-01 --until 2025-05-14
    python copilot_complete.py acme-corp --output my_analysis
"""

import os
import sys
import requests
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import tempfile
import logging
import traceback
import argparse
from datetime import datetime, timedelta
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Set matplotlib to use non-interactive backend to avoid display issues
plt.switch_backend('Agg')

# Set style for better looking plots
plt.style.use('default')
sns.set_palette("husl")

class CopilotCompleteAnalyzer:
    """Complete Copilot Direct Data Access analyzer."""
    
    def __init__(self, enterprise, since_date=None, until_date=None, output_dir=None):
        """Initialize the analyzer."""
        self.enterprise = enterprise
        self.github_token = self._get_github_token()
        
        # Calculate default dates if not provided
        today = datetime.now()
        self.until_date = until_date or (today - timedelta(days=1)).strftime("%Y-%m-%d")
        self.since_date = since_date or (today - timedelta(days=15)).strftime("%Y-%m-%d")
        
        # Set up output directory
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.output_dir = Path(output_dir or f"copilot_analysis_{enterprise}_{timestamp}")
        self.output_dir.mkdir(exist_ok=True)
        
        # Create subdirectories
        (self.output_dir / "plots").mkdir(exist_ok=True)
        (self.output_dir / "reports").mkdir(exist_ok=True)
        (self.output_dir / "data").mkdir(exist_ok=True)
        
        self.df = None
        
    def _get_github_token(self):
        """Get GitHub token from environment."""
        token = os.getenv("GITHUB_TOKEN")
        if not token:
            logger.error("GITHUB_TOKEN environment variable is not set.")
            logger.error("Please export your GitHub token: export GITHUB_TOKEN=your_token_here")
            sys.exit(1)
        return token
    
    def _validate_date_range(self):
        """Validate the date range."""
        try:
            since_date_epoch = datetime.strptime(self.since_date, "%Y-%m-%d").timestamp()
            until_date_epoch = datetime.strptime(self.until_date, "%Y-%m-%d").timestamp()

            if since_date_epoch > until_date_epoch:
                logger.error("Error: since_date cannot be after until_date.")
                return False
                
            date_diff = (until_date_epoch - since_date_epoch) / 86400

            # API allows up to 2 weeks (14 days) per request
            if date_diff > 14:
                logger.error("Error: The date range cannot exceed 14 days.")
                return False
            
            # Check if dates are not more than 365 days in the past
            today = datetime.now().timestamp()
            days_since_start = (today - since_date_epoch) / 86400
            if days_since_start > 365:
                logger.error("Error: since_date cannot be more than 365 days in the past.")
                return False
                
            logger.info(f"Date range is valid: {date_diff:.1f} days")
            return True
            
        except ValueError as e:
            logger.error(f"Date parsing error: {e}")
            return False
    
    def collect_data(self):
        """Collect Copilot data from GitHub API."""
        logger.info("=" * 60)
        logger.info("STEP 1: COLLECTING COPILOT DATA")
        logger.info("=" * 60)
        
        logger.info(f"Enterprise: {self.enterprise}")
        logger.info(f"Date range: {self.since_date} to {self.until_date}")
        
        if not self._validate_date_range():
            return False
        
        # Set up headers
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.github_token}",
            "X-GitHub-Api-Version": "2022-11-28"
        }
        
        # Test API connection
        try:
            logger.info("Testing GitHub API connection...")
            test_response = requests.get("https://api.github.com/rate_limit", headers=headers, timeout=10)
            test_response.raise_for_status()
            rate_limit_info = test_response.json()
            logger.info(f"✅ GitHub API connection successful. Rate limit: {rate_limit_info.get('resources', {}).get('core', {}).get('remaining', 'unknown')} remaining.")
        except requests.exceptions.RequestException as e:
            logger.error(f"❌ GitHub API connection test failed: {e}")
            return False
        
        # Fetch data from API
        url = f"https://api.github.com/enterprises/{self.enterprise}/copilot/direct-data?since={self.since_date}&until={self.until_date}"
        logger.info(f"Fetching data from: {url}")
        
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            json_data = response.json()
            logger.info(f"✅ API response received. Data entries: {len(json_data)}")
        except requests.exceptions.HTTPError as http_err:
            logger.error(f"❌ HTTP error occurred: {http_err}")
            if hasattr(http_err, 'response') and http_err.response is not None:
                logger.error(f"Response status code: {http_err.response.status_code}")
                logger.error(f"Response text: {http_err.response.text}")
            return False
        except Exception as err:
            logger.error(f"❌ An error occurred: {err}")
            return False
        
        # Process blob data
        all_dataframes = []
        
        for entry in json_data:
            date = entry.get("date")
            blob_uris = entry.get("blob_uris", [])
            
            logger.info(f"Processing data for date: {date} ({len(blob_uris)} blob URIs)")
            
            for blob_uri in blob_uris:
                try:
                    response = requests.get(blob_uri)
                    response.raise_for_status()
                    
                    # Read Parquet file
                    with tempfile.NamedTemporaryFile(suffix=".parquet") as temp_file:
                        temp_file.write(response.content)
                        temp_file.flush()
                        df = pd.read_parquet(temp_file.name)
                        all_dataframes.append(df)
                        logger.info(f"  ✅ Processed blob: {df.shape[0]} records, {df.shape[1]} columns")
                        
                except Exception as err:
                    logger.error(f"  ❌ Error processing blob: {err}")
        
        # Combine all data
        if all_dataframes:
            self.df = pd.concat(all_dataframes, ignore_index=True)
            
            # Convert timestamp and add time components
            self.df['hitdttm'] = pd.to_datetime(self.df['hitdttm'])
            self.df['hour'] = self.df['hitdttm'].dt.hour
            self.df['day_of_week'] = self.df['hitdttm'].dt.day_name()
            self.df['date'] = self.df['hitdttm'].dt.date
            
            # Save raw data
            data_file = self.output_dir / "data" / "raw_copilot_data.csv"
            self.df.to_csv(data_file, index=False)
            
            logger.info(f"✅ Data collection complete!")
            logger.info(f"📊 Total records: {len(self.df):,}")
            logger.info(f"👥 Unique users: {self.df['user_login'].nunique()}")
            logger.info(f"📅 Date range: {self.df['hitdttm'].min()} to {self.df['hitdttm'].max()}")
            logger.info(f"💾 Raw data saved to: {data_file}")
            
            return True
        else:
            logger.warning("❌ No data was collected. Check if there are blob URIs in the specified date range.")
            return False
    
    def generate_summary_report(self):
        """Generate comprehensive summary report."""
        logger.info("\n" + "=" * 60)
        logger.info("STEP 2: GENERATING SUMMARY REPORT")
        logger.info("=" * 60)
        
        if self.df is None or len(self.df) == 0:
            logger.error("No data available for analysis")
            return
        
        report = []
        report.append("=" * 80)
        report.append("GITHUB COPILOT DIRECT DATA ACCESS - ANALYSIS REPORT")
        report.append("=" * 80)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"Enterprise: {self.enterprise}")
        report.append(f"Data Period: {self.df['hitdttm'].min()} to {self.df['hitdttm'].max()}")
        report.append(f"Total Records: {len(self.df):,}")
        report.append("")
        
        # Basic statistics
        report.append("BASIC STATISTICS")
        report.append("-" * 40)
        report.append(f"Unique Users: {self.df['user_login'].nunique()}")
        if 'message_id' in self.df.columns:
            report.append(f"Unique Sessions: {self.df['message_id'].nunique()}")
        report.append(f"Date Range: {(self.df['hitdttm'].max() - self.df['hitdttm'].min()).days} days")
        report.append("")
        
        # User engagement
        report.append("TOP 10 MOST ACTIVE USERS")
        report.append("-" * 40)
        top_users = self.df['user_login'].value_counts().head(10)
        for user, count in top_users.items():
            report.append(f"{user}: {count} interactions")
        report.append("")
        
        # Feature usage
        if 'label' in self.df.columns:
            report.append("COPILOT FEATURE USAGE")
            report.append("-" * 40)
            label_counts = self.df['label'].value_counts()
            for label, count in label_counts.items():
                percentage = (count / len(self.df)) * 100
                report.append(f"{label}: {count} ({percentage:.1f}%)")
            report.append("")
        
        # Language distribution
        if 'language' in self.df.columns:
            report.append("TOP PROGRAMMING LANGUAGES")
            report.append("-" * 40)
            lang_counts = self.df['language'].value_counts().head(10)
            for lang, count in lang_counts.items():
                percentage = (count / len(self.df)) * 100
                report.append(f"{lang}: {count} ({percentage:.1f}%)")
            report.append("")
        
        # Time patterns
        report.append("USAGE PATTERNS")
        report.append("-" * 40)
        hourly_usage = self.df.groupby('hour').size().sort_index()
        peak_hour = hourly_usage.idxmax()
        report.append(f"Peak usage hour: {peak_hour}:00 ({hourly_usage[peak_hour]} interactions)")
        
        daily_usage = self.df['day_of_week'].value_counts()
        peak_day = daily_usage.idxmax()
        report.append(f"Most active day: {peak_day} ({daily_usage[peak_day]} interactions)")
        report.append("")
        
        # Code metrics
        if 'lines' in self.df.columns and 'chars' in self.df.columns:
            total_lines = self.df['lines'].sum()
            total_chars = self.df['chars'].sum()
            report.append("CODE METRICS")
            report.append("-" * 40)
            report.append(f"Total lines assisted: {total_lines:,}")
            report.append(f"Total characters assisted: {total_chars:,}")
            if len(self.df) > 0:
                report.append(f"Average lines per interaction: {total_lines/len(self.df):.1f}")
                report.append(f"Average characters per interaction: {total_chars/len(self.df):.1f}")
            report.append("")
        
        # Save report
        report_text = "\n".join(report)
        report_file = self.output_dir / "reports" / "summary_report.txt"
        with open(report_file, 'w') as f:
            f.write(report_text)
        
        logger.info(f"✅ Summary report saved to: {report_file}")
        
        # Print key highlights
        print("\n" + "🔍 KEY INSIGHTS" + "=" * 45)
        print(f"📊 Total Interactions: {len(self.df):,}")
        print(f"👥 Active Users: {self.df['user_login'].nunique()}")
        if 'language' in self.df.columns:
            top_lang = self.df['language'].value_counts().index[0]
            print(f"💻 Top Language: {top_lang}")
        print(f"⏰ Peak Hour: {peak_hour}:00")
        print(f"📅 Most Active Day: {peak_day}")
        print("=" * 60)
    
    def create_visualizations(self):
        """Create comprehensive visualizations."""
        logger.info("\n" + "=" * 60)
        logger.info("STEP 3: CREATING VISUALIZATIONS")
        logger.info("=" * 60)
        
        if self.df is None or len(self.df) == 0:
            logger.error("No data available for visualization")
            return
        
        # Set up the plotting style
        plt.rcParams.update({
            'figure.figsize': (15, 10),
            'font.size': 10,
            'axes.titlesize': 14,
            'axes.labelsize': 12,
            'xtick.labelsize': 10,
            'ytick.labelsize': 10,
            'legend.fontsize': 10
        })
        
        # 1. User Engagement Dashboard
        self._plot_user_engagement()
        
        # 2. Feature Usage Analysis
        self._plot_feature_usage()
        
        # 3. Language Analysis
        if 'language' in self.df.columns:
            self._plot_language_analysis()
        
        # 4. Time Pattern Analysis
        self._plot_time_patterns()
        
        # 5. Environment Analysis
        self._plot_environment_analysis()
        
        logger.info("✅ All visualizations created successfully!")
    
    def _plot_user_engagement(self):
        """Create user engagement visualizations."""
        fig, axes = plt.subplots(2, 2, figsize=(16, 12))
        fig.suptitle('📊 Copilot User Engagement Analysis', fontsize=16, fontweight='bold')
        
        # Top users
        top_users = self.df['user_login'].value_counts().head(10)
        axes[0, 0].barh(range(len(top_users)), top_users.values, color='skyblue')
        axes[0, 0].set_yticks(range(len(top_users)))
        axes[0, 0].set_yticklabels(top_users.index)
        axes[0, 0].set_xlabel('Number of Interactions')
        axes[0, 0].set_title('🏆 Top 10 Most Active Users')
        axes[0, 0].invert_yaxis()
        
        # Daily activity
        daily_activity = self.df.groupby('date').size()
        axes[0, 1].plot(daily_activity.index, daily_activity.values, marker='o', linewidth=2, markersize=6)
        axes[0, 1].set_xlabel('Date')
        axes[0, 1].set_ylabel('Number of Interactions')
        axes[0, 1].set_title('📈 Daily Copilot Activity')
        axes[0, 1].tick_params(axis='x', rotation=45)
        axes[0, 1].grid(True, alpha=0.3)
        
        # Hourly patterns
        hourly_usage = self.df.groupby('hour').size()
        axes[1, 0].bar(hourly_usage.index, hourly_usage.values, color='lightcoral', alpha=0.7)
        axes[1, 0].set_xlabel('Hour of Day')
        axes[1, 0].set_ylabel('Number of Interactions')
        axes[1, 0].set_title('⏰ Usage Patterns by Hour')
        axes[1, 0].set_xticks(range(0, 24, 2))
        axes[1, 0].grid(True, alpha=0.3)
        
        # Day of week patterns
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_usage = self.df['day_of_week'].value_counts().reindex(day_order)
        colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FECA57', '#FF9FF3', '#54A0FF']
        axes[1, 1].bar(day_usage.index, day_usage.values, color=colors)
        axes[1, 1].set_xlabel('Day of Week')
        axes[1, 1].set_ylabel('Number of Interactions')
        axes[1, 1].set_title('📅 Usage Patterns by Day of Week')
        axes[1, 1].tick_params(axis='x', rotation=45)
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plot_file = self.output_dir / "plots" / "user_engagement.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"✅ User engagement plot saved: {plot_file}")
    
    def _plot_feature_usage(self):
        """Create feature usage visualizations."""
        fig, axes = plt.subplots(2, 2, figsize=(16, 12))
        fig.suptitle('🔧 Copilot Feature Usage Analysis', fontsize=16, fontweight='bold')
        
        # Action distribution
        if 'action' in self.df.columns:
            action_counts = self.df['action'].value_counts()
            colors = plt.cm.Set3(np.linspace(0, 1, len(action_counts)))
            axes[0, 0].pie(action_counts.values, labels=action_counts.index, autopct='%1.1f%%', colors=colors)
            axes[0, 0].set_title('🎯 Distribution of Actions')
        
        # Label distribution
        if 'label' in self.df.columns:
            label_counts = self.df['label'].value_counts()
            axes[0, 1].bar(label_counts.index, label_counts.values, color='lightgreen', alpha=0.7)
            axes[0, 1].set_xlabel('Label Type')
            axes[0, 1].set_ylabel('Count')
            axes[0, 1].set_title('🏷️ Copilot Interaction Types')
            axes[0, 1].tick_params(axis='x', rotation=45)
            axes[0, 1].grid(True, alpha=0.3)
        
        # Application usage
        if 'application' in self.df.columns:
            app_counts = self.df['application'].value_counts()
            axes[1, 0].bar(app_counts.index, app_counts.values, color='orange', alpha=0.7)
            axes[1, 0].set_xlabel('Application')
            axes[1, 0].set_ylabel('Count')
            axes[1, 0].set_title('🔨 Copilot Application Usage')
            axes[1, 0].tick_params(axis='x', rotation=45)
            axes[1, 0].grid(True, alpha=0.3)
        
        # Category usage
        if 'category' in self.df.columns:
            cat_counts = self.df['category'].value_counts()
            axes[1, 1].bar(cat_counts.index, cat_counts.values, color='purple', alpha=0.7)
            axes[1, 1].set_xlabel('Category')
            axes[1, 1].set_ylabel('Count')
            axes[1, 1].set_title('📂 Feature Category Usage')
            axes[1, 1].tick_params(axis='x', rotation=45)
            axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plot_file = self.output_dir / "plots" / "feature_usage.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"✅ Feature usage plot saved: {plot_file}")
    
    def _plot_language_analysis(self):
        """Create programming language analysis."""
        fig, axes = plt.subplots(2, 2, figsize=(16, 12))
        fig.suptitle('💻 Programming Language Analysis', fontsize=16, fontweight='bold')
        
        # Top languages
        lang_counts = self.df['language'].value_counts().head(15)
        axes[0, 0].barh(range(len(lang_counts)), lang_counts.values, color='teal', alpha=0.7)
        axes[0, 0].set_yticks(range(len(lang_counts)))
        axes[0, 0].set_yticklabels(lang_counts.index)
        axes[0, 0].set_xlabel('Number of Interactions')
        axes[0, 0].set_title('🥇 Top 15 Programming Languages')
        axes[0, 0].invert_yaxis()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Language pie chart
        top_10_langs = self.df['language'].value_counts().head(10)
        colors = plt.cm.tab10(np.linspace(0, 1, len(top_10_langs)))
        axes[0, 1].pie(top_10_langs.values, labels=top_10_langs.index, autopct='%1.1f%%', colors=colors)
        axes[0, 1].set_title('🎯 Top 10 Languages Distribution')
        
        # Language usage over time
        if len(self.df['date'].unique()) > 1:
            lang_time = self.df.groupby(['date', 'language']).size().unstack(fill_value=0)
            top_langs = self.df['language'].value_counts().head(5).index
            for i, lang in enumerate(top_langs):
                if lang in lang_time.columns:
                    color = plt.cm.tab10(i)
                    axes[1, 0].plot(lang_time.index, lang_time[lang], marker='o', label=lang, color=color, linewidth=2)
            axes[1, 0].set_xlabel('Date')
            axes[1, 0].set_ylabel('Number of Interactions')
            axes[1, 0].set_title('📈 Language Usage Over Time (Top 5)')
            axes[1, 0].legend()
            axes[1, 0].tick_params(axis='x', rotation=45)
            axes[1, 0].grid(True, alpha=0.3)
        
        # Lines of code by language
        if 'lines' in self.df.columns:
            lang_lines = self.df.groupby('language')['lines'].sum().sort_values(ascending=False).head(10)
            axes[1, 1].bar(lang_lines.index, lang_lines.values, color='gold', alpha=0.7)
            axes[1, 1].set_xlabel('Language')
            axes[1, 1].set_ylabel('Total Lines')
            axes[1, 1].set_title('📏 Total Lines by Language (Top 10)')
            axes[1, 1].tick_params(axis='x', rotation=45)
            axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plot_file = self.output_dir / "plots" / "language_analysis.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"✅ Language analysis plot saved: {plot_file}")
    
    def _plot_time_patterns(self):
        """Create time pattern analysis."""
        fig, axes = plt.subplots(2, 2, figsize=(16, 12))
        fig.suptitle('⏰ Time Pattern Analysis', fontsize=16, fontweight='bold')
        
        # Hourly heatmap by day of week
        if len(self.df) > 10:  # Only create heatmap if we have enough data
            pivot_data = self.df.groupby(['day_of_week', 'hour']).size().unstack(fill_value=0)
            day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
            if not pivot_data.empty:
                pivot_data = pivot_data.reindex(day_order, fill_value=0)
                sns.heatmap(pivot_data, ax=axes[0, 0], cmap='YlOrRd', annot=False, fmt='d')
                axes[0, 0].set_title('🔥 Activity Heatmap (Hour vs Day)')
                axes[0, 0].set_xlabel('Hour of Day')
                axes[0, 0].set_ylabel('Day of Week')
        
        # User activity distribution
        user_activity = self.df['user_login'].value_counts()
        axes[0, 1].hist(user_activity.values, bins=20, color='lightblue', alpha=0.7, edgecolor='black')
        axes[0, 1].set_xlabel('Number of Interactions per User')
        axes[0, 1].set_ylabel('Number of Users')
        axes[0, 1].set_title('👥 User Activity Distribution')
        axes[0, 1].grid(True, alpha=0.3)
        
        # Cumulative activity over time
        if len(self.df['date'].unique()) > 1:
            daily_cumulative = self.df.groupby('date').size().cumsum()
            axes[1, 0].plot(daily_cumulative.index, daily_cumulative.values, marker='o', linewidth=3, color='green')
            axes[1, 0].set_xlabel('Date')
            axes[1, 0].set_ylabel('Cumulative Interactions')
            axes[1, 0].set_title('📈 Cumulative Activity Over Time')
            axes[1, 0].tick_params(axis='x', rotation=45)
            axes[1, 0].grid(True, alpha=0.3)
        
        # Peak hours by user
        user_peak_hours = self.df.groupby('user_login')['hour'].apply(lambda x: x.mode().iloc[0] if not x.mode().empty else x.mean())
        axes[1, 1].hist(user_peak_hours.values, bins=24, color='coral', alpha=0.7, edgecolor='black')
        axes[1, 1].set_xlabel('Peak Hour')
        axes[1, 1].set_ylabel('Number of Users')
        axes[1, 1].set_title('⏰ User Peak Hours Distribution')
        axes[1, 1].set_xticks(range(0, 24, 2))
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plot_file = self.output_dir / "plots" / "time_patterns.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"✅ Time patterns plot saved: {plot_file}")
    
    def _plot_environment_analysis(self):
        """Create development environment analysis."""
        fig, axes = plt.subplots(2, 2, figsize=(16, 12))
        fig.suptitle('🖥️ Development Environment Analysis', fontsize=16, fontweight='bold')
        
        # Client distribution
        if 'client' in self.df.columns:
            client_counts = self.df['client'].value_counts()
            colors = plt.cm.tab20(np.linspace(0, 1, len(client_counts)))
            axes[0, 0].pie(client_counts.values, labels=client_counts.index, autopct='%1.1f%%', colors=colors)
            axes[0, 0].set_title('💻 IDE/Client Distribution')
        
        # Device distribution
        if 'device' in self.df.columns:
            device_counts = self.df['device'].value_counts()
            axes[0, 1].bar(device_counts.index, device_counts.values, color='lightsteelblue', alpha=0.7)
            axes[0, 1].set_xlabel('Device Type')
            axes[0, 1].set_ylabel('Count')
            axes[0, 1].set_title('📱 Device Type Distribution')
            axes[0, 1].grid(True, alpha=0.3)
        
        # Client versions
        if 'client_version' in self.df.columns:
            version_counts = self.df['client_version'].value_counts().head(10)
            axes[1, 0].barh(range(len(version_counts)), version_counts.values, color='mediumpurple', alpha=0.7)
            axes[1, 0].set_yticks(range(len(version_counts)))
            axes[1, 0].set_yticklabels(version_counts.index)
            axes[1, 0].set_xlabel('Number of Interactions')
            axes[1, 0].set_title('🔄 Top 10 Client Versions')
            axes[1, 0].invert_yaxis()
            axes[1, 0].grid(True, alpha=0.3)
        
        # Active model
        if 'active_model' in self.df.columns:
            model_counts = self.df['active_model'].value_counts()
            axes[1, 1].bar(model_counts.index, model_counts.values, color='darkseagreen', alpha=0.7)
            axes[1, 1].set_xlabel('Active Model')
            axes[1, 1].set_ylabel('Count')
            axes[1, 1].set_title('🤖 Active Model Distribution')
            axes[1, 1].tick_params(axis='x', rotation=45)
            axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plot_file = self.output_dir / "plots" / "environment_analysis.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        logger.info(f"✅ Environment analysis plot saved: {plot_file}")
    
    def export_detailed_data(self):
        """Export detailed CSV reports."""
        logger.info("\n" + "=" * 60)
        logger.info("STEP 4: EXPORTING DETAILED DATA")
        logger.info("=" * 60)
        
        if self.df is None or len(self.df) == 0:
            logger.error("No data available for export")
            return
        
        data_dir = self.output_dir / "data"
        
        # User activity summary
        user_summary = self.df.groupby('user_login').agg({
            'hitdttm': ['count', 'min', 'max'],
            'lines': 'sum' if 'lines' in self.df.columns else lambda x: 0,
            'chars': 'sum' if 'chars' in self.df.columns else lambda x: 0,
            'language': lambda x: x.mode().iloc[0] if not x.mode().empty else 'unknown'
        }).round(2)
        user_summary.columns = ['total_interactions', 'first_interaction', 'last_interaction', 'total_lines', 'total_chars', 'primary_language']
        user_summary.to_csv(data_dir / "user_activity_summary.csv")
        logger.info(f"✅ User activity summary exported: {data_dir / 'user_activity_summary.csv'}")
        
        # Language summary
        if 'language' in self.df.columns:
            lang_summary = self.df.groupby('language').agg({
                'user_login': 'nunique',
                'hitdttm': 'count',
                'lines': 'sum' if 'lines' in self.df.columns else lambda x: 0,
                'chars': 'sum' if 'chars' in self.df.columns else lambda x: 0
            }).round(2)
            lang_summary.columns = ['unique_users', 'total_interactions', 'total_lines', 'total_chars']
            lang_summary.to_csv(data_dir / "language_summary.csv")
            logger.info(f"✅ Language summary exported: {data_dir / 'language_summary.csv'}")
        
        # Daily activity
        daily_summary = self.df.groupby('date').agg({
            'user_login': 'nunique',
            'hitdttm': 'count',
            'lines': 'sum' if 'lines' in self.df.columns else lambda x: 0,
            'chars': 'sum' if 'chars' in self.df.columns else lambda x: 0
        }).round(2)
        daily_summary.columns = ['unique_users', 'total_interactions', 'total_lines', 'total_chars']
        daily_summary.to_csv(data_dir / "daily_activity_summary.csv")
        logger.info(f"✅ Daily activity summary exported: {data_dir / 'daily_activity_summary.csv'}")
    
    def run_complete_analysis(self):
        """Run the complete analysis pipeline."""
        print("🚀 GitHub Copilot Complete Analysis Tool")
        print("=" * 50)
        print(f"Enterprise: {self.enterprise}")
        print(f"Date Range: {self.since_date} to {self.until_date}")
        print(f"Output Directory: {self.output_dir}")
        print("")
        
        # Step 1: Collect data
        if not self.collect_data():
            print("❌ Data collection failed. Exiting.")
            return False
        
        # Step 2: Generate summary report
        self.generate_summary_report()
        
        # Step 3: Create visualizations
        self.create_visualizations()
        
        # Step 4: Export detailed data
        self.export_detailed_data()
        
        # Final summary
        print("\n" + "🎉 ANALYSIS COMPLETE!" + "=" * 35)
        print(f"📁 Results Directory: {self.output_dir}")
        print(f"📊 Visualizations: {self.output_dir}/plots/")
        print(f"📋 Reports: {self.output_dir}/reports/")
        print(f"📈 Data Exports: {self.output_dir}/data/")
        print("")
        print("📊 Generated Files:")
        print("  🎯 user_engagement.png - User activity patterns")
        print("  🔧 feature_usage.png - Copilot feature analysis")
        print("  💻 language_analysis.png - Programming language insights")
        print("  ⏰ time_patterns.png - Temporal usage patterns")
        print("  🖥️ environment_analysis.png - Development environment stats")
        print("  📄 summary_report.txt - Comprehensive text report")
        print("  📊 Detailed CSV exports for further analysis")
        print("")
        print("🎯 Next Steps:")
        print("  • Review the summary report for key insights")
        print("  • Examine visualizations for usage patterns")
        print("  • Use CSV exports for custom analysis")
        print("  • Share findings with development teams")
        print("")
        print("✨ Happy analyzing!")
        
        return True

def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description='Complete GitHub Copilot Direct Data Access analysis tool.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  python copilot_complete.py fabrikam
  python copilot_complete.py myenterprise --since 2025-05-01 --until 2025-05-14
  python copilot_complete.py acme-corp --output my_analysis_dir
        '''
    )
    
    parser.add_argument('enterprise', 
                       help='The enterprise name (slug version) or enterprise ID')
    
    # Calculate default dates
    today = datetime.now()
    until_default = (today - timedelta(days=1)).strftime("%Y-%m-%d")
    since_default = (today - timedelta(days=15)).strftime("%Y-%m-%d")
    
    parser.add_argument('--since', 
                       default=since_default,
                       help=f'Start date in YYYY-MM-DD format (default: {since_default})')
    
    parser.add_argument('--until', 
                       default=until_default,
                       help=f'End date in YYYY-MM-DD format (default: {until_default})')
    
    parser.add_argument('--output', 
                       help='Output directory for analysis results (default: auto-generated)')
    
    args = parser.parse_args()
    
    # Check dependencies
    try:
        import pandas
        import matplotlib
        import seaborn
        import requests
    except ImportError as e:
        print(f"❌ Missing required package: {e}")
        print("Please install with: pip install pandas requests pyarrow matplotlib seaborn")
        sys.exit(1)
    
    # Run analysis
    analyzer = CopilotCompleteAnalyzer(
        enterprise=args.enterprise,
        since_date=args.since,
        until_date=args.until,
        output_dir=args.output
    )
    
    success = analyzer.run_complete_analysis()
    
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
