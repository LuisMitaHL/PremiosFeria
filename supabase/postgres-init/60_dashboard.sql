-- 60_dashboard.sql — the attendee's home screen, answered in one read (spec 013).
--
-- Every figure on that screen is a question about the same person at the same
-- instant: what they hold, how far they have got, what is within reach, what is
-- happening now. Asked one request at a time they drift apart, and the pair
-- that matters most drifts worst: a balance read before a handover, next to a
-- count of prizes read after it, promises something the catalogue has already
-- taken away. Answered together they cannot disagree.
--
-- The count of prizes within reach is why this file exists. It depends on cost,
-- on stock, on two withdrawal flags and on what this attendee already took home
-- — four things spread across specs 021, 022 and 023. Assembled in the browser
-- it would mean shipping the whole catalogue and every claim to a phone in
-- order to count them there, and it would still be a count of one moment
-- against a balance from another.

CREATE OR REPLACE FUNCTION participant_dashboard()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_p participants%ROWTYPE;
  v_published INT;
  v_reachable INT;
  v_unclaimed INT;
  v_next INT;
  v_claimed INT;
  v_state TEXT;
BEGIN
  -- Identity is never a parameter (constitution IV). Whose figures these are is
  -- decided here, from the session; the screen has no say in it and nothing it
  -- sends can change the answer, because it sends nothing.
  SELECT * INTO v_p FROM participants WHERE auth_user_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Regístrate para participar.');
  END IF;

  -- The catalogue as an attendee sees it. A withdrawn prize, or a prize of a
  -- stand that left the fair, is not part of it any more (spec 021 R19a,
  -- spec 023 R15) — and counting one as reachable would send somebody across
  -- the hall for a table that is no longer there.
  --
  -- One pass over that catalogue answers all four questions, because each is
  -- the same rows under a different filter.
  SELECT count(*),
         count(*) FILTER (WHERE r.in_stock AND r.affordable AND NOT r.claimed),
         count(*) FILTER (WHERE NOT r.claimed),
         min(r.cost - v_p.points) FILTER (WHERE r.in_stock AND NOT r.affordable AND NOT r.claimed)
  INTO v_published, v_reachable, v_unclaimed, v_next
  FROM (
    SELECT rw.cost,
           rw.stock > 0        AS in_stock,
           rw.cost <= v_p.points AS affordable,
           EXISTS (SELECT 1 FROM claimed_rewards cr
                   WHERE cr.participant_id = v_p.id AND cr.reward_id = rw.id) AS claimed
    FROM rewards rw
    JOIN communities c ON c.id = rw.community_id
    WHERE NOT rw.is_withdrawn AND NOT c.is_withdrawn
  ) r;

  -- Prizes already taken home count whatever became of them afterwards: a
  -- reward withdrawn from the catalogue does not un-give the one in somebody's
  -- backpack.
  SELECT count(*) INTO v_claimed FROM claimed_rewards WHERE participant_id = v_p.id;

  -- Zero reachable is not one situation but four, and they are not the same
  -- news. Which one it is follows from the data, so it is decided here; only
  -- the wording is the screen's business.
  v_state := CASE
    -- A barred attendee (spec 022) can reach nothing, whatever the balance
    -- says, so the count is never the answer to give them.
    WHEN v_p.claims_barred      THEN 'barred'
    WHEN v_published = 0        THEN 'none_published'
    WHEN v_reachable > 0        THEN 'reachable'
    WHEN v_next IS NOT NULL     THEN 'short'
    WHEN v_unclaimed = 0        THEN 'all_claimed'
    ELSE 'none_available'
  END;

  RETURN jsonb_build_object(
    -- The balance travels with the figures derived from it. Read separately it
    -- could contradict them on screen.
    'points',              v_p.points,
    'claimsBarred',        v_p.claims_barred,
    -- Every stand, withdrawn ones included: the list of chips under this figure
    -- shows them all, and a total that quietly dropped one would read as an
    -- arithmetic error — worse, a visit already made would stop counting.
    'standsTotal',         (SELECT count(*) FROM communities),
    'standsVisited',       (SELECT count(DISTINCT community_id) FROM scans
                            WHERE participant_id = v_p.id AND type = 'visit'),
    -- Completions, not stands. A stand may run three activities since spec 019,
    -- and counting stands was the same number only while it ran one.
    'activitiesPublished', (SELECT count(*) FROM activities),
    'activitiesCompleted', (SELECT count(*) FROM scans
                            WHERE participant_id = v_p.id AND activity_id IS NOT NULL),
    'rewardsClaimed',      v_claimed,
    'rewardsPublished',    v_published,
    'rewardsReachable',    v_reachable,
    'pointsToNext',        v_next,
    'reachState',          v_state,
    -- What is on right now, in summary. The state is derived, never stored
    -- (52_activities.sql), so an activity whose duration elapsed with nobody's
    -- screen open drops out of here by itself. A withdrawn stand's activity is
    -- left out entirely: this list is an invitation to walk somewhere.
    'running',             (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',          a.id,
        'name',        a.name,
        'stand',       c.name,
        'standNumber', c.stand_number,
        'icon',        c.emoji,
        'isMainEvent', a.is_main_event,
        'completed',   EXISTS (SELECT 1 FROM scans s
                               WHERE s.participant_id = v_p.id AND s.activity_id = a.id)
      ) ORDER BY a.is_main_event DESC, c.name), '[]'::jsonb)
      FROM activities a
      JOIN communities c ON c.id = a.community_id
      WHERE activity_state(a) = 'running' AND NOT c.is_withdrawn
    )
  );
END;
$fn$;

-- STABLE and read-only on purpose: this function is the home screen, and the
-- home screen awards, spends and changes nothing (spec 013, R13).
GRANT EXECUTE ON FUNCTION participant_dashboard() TO anon, authenticated;
