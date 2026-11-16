counts = CampaignRecipient.statuses.keys.index_with { |status| @status_counts.fetch(status, 0) }

json.audience counts.values.sum
json.sent @accepted_count
# A read message was also delivered.
json.delivered counts.values_at('delivered', 'read').sum
json.read counts['read']
json.failed counts['failed']
json.skipped counts['skipped']
json.status_counts counts
