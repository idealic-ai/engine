-- Email QA bench — proven probe queries (parametrize :ORG, :LINK_ID, :EMAIL, :CLAIM_ID, :REF)
-- All read-only. jsonb columns (to_emails/cc_emails) need ::text before string ops.

-- 1. LINK FORENSICS — the first query for any misroute
SELECT l.id, l.review_status, l.confidence, l.proposed_claim_id, l.claim_id,
       l.extracted_claim_number, l.extracted_address, l.candidate_claim_ids,
       l.match_sources, l.layer4_decision, l.layer4_dropped_claim_ids,
       l.fetch_quality, left(l.rationale, 200) rationale
FROM email_message_claim_link l WHERE l.id = :LINK_ID;

-- 2. THREAD/CONVERSATION VIEW — all links for a sender+subject family
SELECT l.id, l.review_status, l.proposed_claim_id, l.claim_id, m.received_at::date, m.subject
FROM email_message_claim_link l
JOIN email_message m ON m.id = l.msft_message_id
JOIN email_tenant t ON t.id = m.tenant_id
WHERE t.organization_id = :ORG AND lower(m.from_email) = lower(:EMAIL)
ORDER BY m.received_at;

-- 3. SENDER BINDINGS — the axis-eligibility view (multi-bind = no rescue)
SELECT cc.claim_id, c.file_number, left(c.title,30) title, c.intake_status, cc.source, cc.status,
       cc.evidence_msft_message_id, cc.created_at::date
FROM contact_email ce
JOIN contact ct ON ct.person_id = ce.person_id
JOIN claim_contact cc ON cc.contact_id = ct.id
JOIN claim c ON c.id = cc.claim_id
WHERE lower(ce.email) = lower(:EMAIL);

-- 4. TWIN CENSUS — same-name claims with richness signals
SELECT c.id, c.file_number, c.title, c.intake_status, p.address, c.created_at::date,
       array_to_string(c.carrier_claim_numbers, ',') refs,
       (SELECT count(*) FROM email_message_claim_link l WHERE l.claim_id = c.id AND l.review_status IN ('approved','auto_approved')) links,
       (SELECT count(*) FROM claim_document_version v WHERE v.claim_id = c.id AND v.deleted_at IS NULL) docs
FROM claim c LEFT JOIN property p ON p.id = c.property_id
WHERE c.organization_id = :ORG AND c.title ILIKE '%' || :NAME || '%';

-- 5. REF OWNERSHIP — who carries this ref (normalized)?
SELECT id, file_number, left(title,30), array_to_string(carrier_claim_numbers,',')
FROM claim
WHERE organization_id = :ORG AND EXISTS (
  SELECT 1 FROM unnest(carrier_claim_numbers) r
  WHERE upper(regexp_replace(r,'[^A-Za-z0-9]','','g')) = upper(regexp_replace(:REF,'[^A-Za-z0-9]','','g')));

-- 6. COLLISION CHECK before promoting a ref (incl. zero-pad core fold)
SELECT c.id, left(c.title,30), r FROM claim c, unnest(c.carrier_claim_numbers) r
WHERE c.organization_id = :ORG
  AND (upper(regexp_replace(r,'[^A-Za-z0-9]','','g')) = upper(regexp_replace(:REF,'[^A-Za-z0-9]','','g'))
       OR (ltrim(regexp_replace(upper(r),'[^0-9]','','g'),'0') <> ''
           AND ltrim(regexp_replace(upper(r),'[^0-9]','','g'),'0')
             = ltrim(regexp_replace(upper(:REF),'[^0-9]','','g'),'0')));

-- 7. MINED-REFS PASS — approved-mail refs >=5 votes not on the bound claim
SELECT c.id claim_id, left(c.title,32) title, l.extracted_claim_number ref, count(*) votes,
       array_to_string(c.carrier_claim_numbers,',') current_refs
FROM email_message_claim_link l
JOIN claim c ON c.id = l.claim_id
WHERE c.organization_id = :ORG AND l.review_status IN ('approved','auto_approved')
  AND l.extracted_claim_number IS NOT NULL AND l.extracted_claim_number <> ''
  AND upper(regexp_replace(l.extracted_claim_number,'[^A-Za-z0-9]','','g')) NOT IN (
    SELECT upper(regexp_replace(unnest(c2.carrier_claim_numbers),'[^A-Za-z0-9]','','g'))
    FROM claim c2 WHERE c2.id = c.id AND c2.carrier_claim_numbers IS NOT NULL)
GROUP BY 1,2,3,5 HAVING count(*) >= 5 ORDER BY 4 DESC;

-- 8. ALIAS CENSUS — unresolvable claimmail alias refs on queue links
WITH alias_rows AS (
  SELECT l.id link_id, l.review_status,
         (regexp_match(lower(m.to_emails::text||','||COALESCE(m.cc_emails::text,'')),
                       '([a-z]+)-([a-z0-9]{6,})@claimmail\.net'))[2] alias_ref,
         m.subject
  FROM email_message_claim_link l
  JOIN email_message m ON m.id = l.msft_message_id
  JOIN email_tenant t ON t.id = m.tenant_id
  WHERE t.organization_id = :ORG AND l.review_status IN ('pending_review','parked','lead_filed')
    AND (m.to_emails::text||COALESCE(m.cc_emails::text,'')) ILIKE '%@claimmail.net%')
SELECT alias_ref, count(*) links, min(left(subject,45)) sample
FROM alias_rows
WHERE alias_ref IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM claim c WHERE c.organization_id = :ORG
    AND (upper(regexp_replace(COALESCE(c.file_number,''),'[^A-Za-z0-9]','','g')) = upper(alias_ref)
      OR EXISTS (SELECT 1 FROM unnest(c.carrier_claim_numbers) r
                 WHERE upper(regexp_replace(r,'[^A-Za-z0-9]','','g')) = upper(alias_ref))))
GROUP BY 1 ORDER BY 2 DESC;

-- 9. ALIAS -> CLAIM MAPPING — approved-sibling votes (accept >=5 votes AND >=90% dominance)
--    (compose with #8's alias_rows over ALL statuses; rank by votes desc, take rn=1)

-- 10. QUEUE DECOMPOSITION — rationale heads for an org's pending cohort
SELECT COALESCE(substring(l.rationale from '^\[([a-z0-9_]+)'),'(none)') head, count(*)
FROM email_message_claim_link l
JOIN email_message m ON m.id = l.msft_message_id
JOIN email_tenant t ON t.id = m.tenant_id
WHERE t.organization_id = :ORG AND l.review_status = 'pending_review'
GROUP BY 1 ORDER BY 2 DESC;

-- 11. DROPPED-PROPOSAL SIGNATURE SWEEP — instances of the class org-wide
SELECT l.id, l.proposed_claim_id, left(l.rationale,80)
FROM email_message_claim_link l
JOIN email_message m ON m.id = l.msft_message_id
JOIN email_tenant t ON t.id = m.tenant_id
WHERE t.organization_id = :ORG AND l.review_status = 'pending_review'
  AND l.rationale LIKE '%layer4_single_candidate_dropped%' AND l.proposed_claim_id IS NOT NULL;
