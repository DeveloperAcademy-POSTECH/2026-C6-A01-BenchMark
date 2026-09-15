CREATE TABLE mat_activity_events (
  id uuid PRIMARY KEY,
  visit_id uuid NOT NULL,
  session_id uuid NOT NULL,
  name text NOT NULL CHECK (name IN ('page_view','scroll_depth','active_time','link_click','reaction_attempt','reaction_success','reaction_failure','reservation_attempt','reservation_success','reservation_failure','photo_selected')),
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  path text NOT NULL CHECK (octet_length(path) <= 64),
  story_id uuid,
  properties jsonb NOT NULL CHECK (jsonb_typeof(properties) = 'object' AND octet_length(properties::text) <= 256)
);
CREATE INDEX mat_activity_period ON mat_activity_events (occurred_at DESC, id DESC);
CREATE INDEX mat_activity_received ON mat_activity_events (received_at);
CREATE INDEX mat_activity_story ON mat_activity_events (story_id, occurred_at DESC);
CREATE INDEX mat_activity_name ON mat_activity_events (name, occurred_at DESC);
CREATE UNIQUE INDEX mat_activity_one_view ON mat_activity_events (visit_id) WHERE name = 'page_view';
CREATE UNIQUE INDEX mat_activity_one_depth ON mat_activity_events (visit_id, (properties->>'percent')) WHERE name = 'scroll_depth';
