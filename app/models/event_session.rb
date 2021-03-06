# frozen_string_literal: true

class EventSession < ApplicationRecord
  include PresenceTrackingBoolean

  belongs_to :location, optional: true

  validates :starts_at, :ends_at, :name, presence: true
  validates :name, uniqueness: { scope: [:event_id] }
  validate on: :create do
    if starts_at && starts_at < Time.zone.now
      errors.add(:starts_at, 'must start in the future') unless event&.historical?
    end
  end
  validate do
    errors.add(:ends_at, 'must be after session start time') if starts_at && ends_at && ends_at < starts_at
  end
  validate do
    if required_for_students && volunteers_only
      errors.add(:base, 'A session cannot be both Required for Students and Volunteers Only')
    end
  end

  belongs_to :event, inverse_of: :event_sessions, optional: true
  has_many :rsvp_sessions, dependent: :destroy
  has_many :rsvps, through: :rsvp_sessions

  after_save :update_event_times
  after_destroy :update_event_times

  after_create :update_counter_cache
  after_save do
    update_counter_cache if saved_change_to_attribute?(:location_id)
  end
  after_destroy :update_counter_cache

  add_presence_tracking_boolean(:location_overridden, :location_id)

  def true_location
    location || event.location
  end

  def update_event_times
    return unless event

    # TODO: This 'reload' shouldn't be needed, but without it, the
    # following minimum/maximum statements return 'nil' when
    # initially creating an event and its session. Booo!
    event.reload
    event.update_columns(
      starts_at: event.event_sessions.minimum('event_sessions.starts_at'),
      ends_at: event.event_sessions.maximum('event_sessions.ends_at')
    )
  end

  def starts_at
    event&.persisted? ? date_in_time_zone(:starts_at) : self[:starts_at]
  end

  def ends_at
    event&.persisted? ? date_in_time_zone(:ends_at) : self[:ends_at]
  end

  def session_date
    (starts_at || Date.current).strftime('%Y-%m-%d')
  end

  def date_in_time_zone(start_or_end)
    self[start_or_end].in_time_zone(ActiveSupport::TimeZone.new(event.time_zone))
  end

  def any_rsvps?
    persisted? && rsvps.any?
  end

  def update_counter_cache
    location.try(:reset_events_count)
    return unless saved_change_to_attribute?(:location_id) && saved_changes[:location_id].first

    Location.find(saved_changes[:location_id].first).reset_events_count
  end
end
