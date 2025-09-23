#!/usr/bin/env python3
"""
Script to generate graphs from Copilot JSON data file.
Usage: plot_copilot_json.py <json_file> <output_dir>
"""
import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
import json

if len(sys.argv) != 3:
    print("Usage: plot_copilot_json.py <json_file> <output_dir>")
    sys.exit(1)

json_file = sys.argv[1]
output_dir = sys.argv[2]
os.makedirs(output_dir, exist_ok=True)

data = []
with open(json_file, 'r') as f:
    for line in f:
        data.append(json.loads(line))

df = pd.DataFrame(data)



# Copilot Enterprise Dashboard: User-Level Metrics Export
TOP_N = 10
df_user = df.groupby('user_login').agg({
    'code_generation_activity_count': 'sum',
    'code_acceptance_activity_count': 'sum',
    'user_initiated_interaction_count': 'sum'
}).sort_values('code_generation_activity_count', ascending=False)

# 1. User code activity (generations and acceptances)
df_top = df_user.head(TOP_N).copy()
if len(df_user) > TOP_N:
    other = df_user.iloc[TOP_N:].sum()
    other.name = 'Other'
    df_top = pd.concat([df_top, pd.DataFrame([other])])
df_top = df_top[['code_generation_activity_count', 'code_acceptance_activity_count']]
ax = df_top.plot(kind='barh', stacked=False, figsize=(10, 6))
plt.title(f'Copilot Enterprise Dashboard: User Code Activity (Top {TOP_N} + Other)')
plt.xlabel('Count')
plt.ylabel('User')
plt.tight_layout()
for i, (gen, acc) in enumerate(zip(df_top['code_generation_activity_count'], df_top['code_acceptance_activity_count'])):
    ax.text(gen + max(df_top['code_generation_activity_count']) * 0.01, i - 0.15, str(int(gen)), va='center', fontsize=8, color='blue')
    ax.text(acc + max(df_top['code_generation_activity_count']) * 0.01, i + 0.15, str(int(acc)), va='center', fontsize=8, color='orange')
plt.savefig(os.path.join(output_dir, 'dashboard_user_code_activity.png'))
plt.close()

# 2. User engagement over time (heatmap for top users)
import numpy as np
top_users = df_user.head(TOP_N).index.tolist()
df_heat = df[df['user_login'].isin(top_users)].groupby(['user_login', 'day'])['code_generation_activity_count'].sum().unstack(fill_value=0)
plt.figure(figsize=(12, 6))
import seaborn as sns
sns.heatmap(df_heat, cmap='Blues', annot=False, cbar_kws={'label': 'Code Generations'})
plt.title(f'Copilot Enterprise Dashboard: User Engagement Over Time (Top {TOP_N})')
plt.ylabel('User')
plt.xlabel('Day')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'dashboard_user_engagement_heatmap.png'))
plt.close()

# 3. Feature usage by user (stacked bar for top users)
feature_user = {}
for row in data:
    user = row['user_login']
    for feat in row.get('totals_by_feature', []):
        feature = feat['feature']
        feature_user.setdefault(user, {}).setdefault(feature, 0)
        feature_user[user][feature] += feat['code_generation_activity_count']
feature_user_df = pd.DataFrame(feature_user).fillna(0).T
feature_user_df_top = feature_user_df.loc[top_users]
feature_user_df_top.plot(kind='bar', stacked=True, figsize=(12, 6))
plt.title(f'Copilot Enterprise Dashboard: Feature Usage by User (Top {TOP_N})')
plt.ylabel('Code Generations')
plt.xlabel('User')
plt.xticks(rotation=45, ha='right')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'dashboard_feature_usage_by_user.png'))
plt.close()

# 4. Acceptance rate per user (bar chart)
df_user['acceptance_rate'] = df_user['code_acceptance_activity_count'] / df_user['code_generation_activity_count']
df_user['acceptance_rate'] = df_user['acceptance_rate'].fillna(0)
df_acc = df_user.head(TOP_N).copy()
if len(df_user) > TOP_N:
    other = df_user.iloc[TOP_N:].mean(numeric_only=True)
    other.name = 'Other'
    df_acc = pd.concat([df_acc, pd.DataFrame([other])])
ax = df_acc['acceptance_rate'].plot(kind='barh', figsize=(10, 6), color='green')
plt.title(f'Copilot Enterprise Dashboard: Acceptance Rate per User (Top {TOP_N} + Other)')
plt.xlabel('Acceptance Rate')
plt.ylabel('User')
plt.xlim(0, 1)
plt.tight_layout()
for i, v in enumerate(df_acc['acceptance_rate']):
    ax.text(v + 0.01, i, f'{v:.2f}', va='center', fontsize=8, color='green')
plt.savefig(os.path.join(output_dir, 'dashboard_acceptance_rate_per_user.png'))
plt.close()

# 5. IDE usage per user (stacked bar for top users)
ide_user = {}
for row in data:
    user = row['user_login']
    for ide in row.get('totals_by_ide', []):
        ide_name = ide['ide']
        ide_user.setdefault(user, {}).setdefault(ide_name, 0)
        ide_user[user][ide_name] += ide['code_generation_activity_count']
ide_user_df = pd.DataFrame(ide_user).fillna(0).T
ide_user_df_top = ide_user_df.loc[top_users]
ide_user_df_top.plot(kind='bar', stacked=True, figsize=(12, 6))
plt.title(f'Copilot Enterprise Dashboard: IDE Usage by User (Top {TOP_N})')
plt.ylabel('Code Generations')
plt.xlabel('User')
plt.xticks(rotation=45, ha='right')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'dashboard_ide_usage_by_user.png'))
plt.close()

# 6. Language diversity per user (bar chart for top users)
lang_user = {}
for row in data:
    user = row['user_login']
    for lang in row.get('totals_by_language_feature', []):
        language = lang['language'] or 'unknown'
        if lang['code_generation_activity_count'] > 0:
            lang_user.setdefault(user, set()).add(language)
lang_diversity = {u: len(langs) for u, langs in lang_user.items()}
lang_diversity_df = pd.Series(lang_diversity).loc[top_users]
lang_diversity_df.plot(kind='bar', figsize=(10, 6), color='purple')
plt.title(f'Copilot Enterprise Dashboard: Language Diversity per User (Top {TOP_N})')
plt.ylabel('Number of Languages')
plt.xlabel('User')
plt.xticks(rotation=45, ha='right')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, 'dashboard_language_diversity_per_user.png'))
plt.close()

print(f"Graphs saved to {output_dir}")

