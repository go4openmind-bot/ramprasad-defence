-- =============================================================================
-- sample_data.sql — demonstration data for Ramprasad Defence
-- Run AFTER combined_setup.sql, in Supabase Dashboard > SQL Editor.
-- Safe to re-run: every insert uses a fixed id with ON CONFLICT (id) DO NOTHING.
-- Dates are relative to CURRENT_DATE so the dashboard/risk views stay meaningful.
-- NOTE: no document files are included; upload real files through the app.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------------
insert into public.customers (id, code, name, customer_type, address_line1, city, state, pincode, country, gstin, email, phone, status) values
 ('00000000-0000-0000-0000-000000000101','CUST-ARMY','Ministry of Defence - Army','mod','South Block','New Delhi','Delhi','110011','India','07AAAGM0289C1ZV','procurement@army.example','011-23010000','active'),
 ('00000000-0000-0000-0000-000000000102','CUST-NAVY','Indian Navy - Naval Dockyard','mod','Naval Dockyard Road','Mumbai','Maharashtra','400001','India','27AAAGM0289C2ZW','procurement@navy.example','022-22660000','active'),
 ('00000000-0000-0000-0000-000000000103','CUST-BSF','Border Security Force','paramilitary','Block 10, CGO Complex','New Delhi','Delhi','110003','India','07AAAGM0289C3ZX','procurement@bsf.example','011-24360000','active')
on conflict (id) do nothing;

insert into public.customer_contacts (id, customer_id, name, designation, email, phone, is_primary) values
 ('00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000101','Maj. R. Sharma','Procurement Officer','sharma@army.example','9810000001',true),
 ('00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000102','Cdr. A. Nair','Technical Officer','nair@navy.example','9820000002',true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Products
-- ---------------------------------------------------------------------------
insert into public.products (id, code, name, description, category, unit, hsn_code, manufacturer, part_number, is_serialized, status) values
 ('00000000-0000-0000-0000-000000000201','P-RADIO','VHF Radio Set','Multiband tactical VHF radio set','Communication','NO','85176290','Alpha Defence','AD-RS-500',true,'active'),
 ('00000000-0000-0000-0000-000000000202','P-ANT','Whip Antenna 5 m','Telescopic whip antenna','Communication','NO','85177090','Alpha Defence','AD-ANT-5',false,'active'),
 ('00000000-0000-0000-0000-000000000203','P-BATT','Li-Ion Battery Pack','Rechargeable battery pack for radio set','Power','NO','85076000','Zenith Power','ZP-BAT-12',true,'active'),
 ('00000000-0000-0000-0000-000000000204','P-GPS','GPS Module','Embedded GPS receiver module','Navigation','NO','85269110','Zenith Power','ZP-GPS-7',true,'active')
on conflict (id) do nothing;

insert into public.product_specifications (id, product_id, spec_key, spec_value, unit, sort_order) values
 ('00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000201','Frequency range','30-88','MHz',1),
 ('00000000-0000-0000-0000-000000000602','00000000-0000-0000-0000-000000000201','Output power','5','W',2)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- OEMs
-- ---------------------------------------------------------------------------
insert into public.oems (id, code, name, oem_type, address_line1, city, state, pincode, country, gstin, email, phone, payment_terms, status) values
 ('00000000-0000-0000-0000-000000000301','OEM-BEL','Bharat Electronics Ltd','Defence PSU','Outer Ring Road','Bengaluru','Karnataka','560045','India','29AAACB1234D1Z5','sales@bel.example','080-25000000','30% advance, 70% on delivery','active'),
 ('00000000-0000-0000-0000-000000000302','OEM-ADS','Alpha Defence Systems Pvt Ltd','Private','MIDC Industrial Area','Pune','Maharashtra','411026','India','27AAECA5678E1Z2','sales@alpha.example','020-27000000','50% advance, 50% on delivery','active'),
 ('00000000-0000-0000-0000-000000000303','OEM-ZEN','Zenith Electronics Pvt Ltd','Private','Electronic City','Noida','Uttar Pradesh','201301','India','09AAECZ9012F1Z9','sales@zenith.example','0120-4000000','100% on delivery','active')
on conflict (id) do nothing;

insert into public.oem_contacts (id, oem_id, name, designation, email, phone, is_primary) values
 ('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000301','S. Iyer','Key Account Manager','iyer@bel.example','9900000001',true),
 ('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000302','P. Deshmukh','Sales Head','deshmukh@alpha.example','9910000002',true)
on conflict (id) do nothing;

insert into public.oem_products (id, oem_id, product_id, oem_part_number, lead_time_days, moq, currency, status) values
 ('00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000201','BEL-RS-500',30,5,'INR','active'),
 ('00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000202','BEL-ANT-5',30,5,'INR','active'),
 ('00000000-0000-0000-0000-000000000703','00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000203','ADS-BAT-12',45,10,'INR','active')
on conflict (id) do nothing;

insert into public.oem_price_history (id, oem_id, product_id, unit_price, currency, valid_from, source, reference) values
 ('00000000-0000-0000-0000-000000000801','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000201',31500,'INR',current_date - 10,'quote','BEL quote'),
 ('00000000-0000-0000-0000-000000000802','00000000-0000-0000-0000-000000000303','00000000-0000-0000-0000-000000000203',8600,'INR',current_date - 20,'verbal','Zenith verbal')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Opportunities / requirements / compliance
-- ---------------------------------------------------------------------------
insert into public.opportunities (id, customer_id, title, description, source, estimated_value, currency, probability, expected_close_date, stage, notes) values
 ('00000000-0000-0000-0000-0000000002a1','00000000-0000-0000-0000-000000000102','Naval Dockyard comms upgrade','Upgrade of shipboard VHF communication sets','direct',5000000,'INR',60,current_date + 30,'proposal','Awaiting technical clarification')
on conflict (id) do nothing;

insert into public.requirements (id, opportunity_id, description, requirement_type, priority, status, due_date, notes) values
 ('00000000-0000-0000-0000-0000000002b1','00000000-0000-0000-0000-0000000002a1','Night-vision compatible radio display','technical','high','open',current_date + 20,'Confirm with Navy')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Tenders (a spread of statuses for the dashboard)
-- ---------------------------------------------------------------------------
insert into public.tenders (id, tender_no, customer_id, title, description, source, category, received_date, bid_due_date, emd_amount, emd_exempt, currency, estimated_value, priority, status, notes) values
 ('00000000-0000-0000-0000-000000000901','TND-2026-001','00000000-0000-0000-0000-000000000101','Supply of VHF Radio Sets - Army','Supply of 100 multiband VHF radio sets with ancillaries','GeM','Communication',current_date - 5,current_date + 20,250000,false,'INR',4800000,'high','new','Fresh enquiry'),
 ('00000000-0000-0000-0000-000000000902','TND-2026-002','00000000-0000-0000-0000-000000000102','Shipboard Antenna Systems - Navy','Whip antenna systems for naval vessels','MoD','Communication',current_date - 10,current_date + 5,150000,false,'INR',1800000,'critical','under_review','Closing soon'),
 ('00000000-0000-0000-0000-000000000903','TND-2026-003','00000000-0000-0000-0000-000000000103','Battery Packs - BSF','Li-Ion battery packs for field radio sets','direct','Power',current_date - 25,current_date - 2,50000,false,'INR',600000,'medium','submitted','Bid submitted'),
 ('00000000-0000-0000-0000-000000000904','TND-2026-004','00000000-0000-0000-0000-000000000101','GPS Modules - Army','Embedded GPS receiver modules','GeM','Navigation',current_date - 45,current_date - 30,75000,true,'INR',900000,'high','won','Order expected'),
 ('00000000-0000-0000-0000-000000000905','TND-2026-005','00000000-0000-0000-0000-000000000102','Legacy Radio Spares - Navy','Spares for legacy radio sets','MoD','Spares',current_date - 60,current_date - 40,0,true,'INR',400000,'low','lost','Lost on price')
on conflict (id) do nothing;

insert into public.compliance_items (id, tender_id, requirement, reference_clause, is_mandatory, compliance_status, evidence) values
 ('00000000-0000-0000-0000-0000000002c1','00000000-0000-0000-0000-000000000901','EMD submitted with bid','Clause 4.2',true,'compliant','EMD DD no. 556677'),
 ('00000000-0000-0000-0000-0000000002c2','00000000-0000-0000-0000-000000000901','ISO 9001 certificate','Clause 7.1',true,'pending',null)
on conflict (id) do nothing;

insert into public.tender_requirements (id, tender_id, line_no, product_id, description, specification, quantity, unit, feasibility, compliance_status) values
 ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000901',1,'00000000-0000-0000-0000-000000000201','VHF Radio Set','30-88 MHz, 5 W, ruggedised',100,'NO','feasible','compliant'),
 ('00000000-0000-0000-0000-000000000a02','00000000-0000-0000-0000-000000000901',2,'00000000-0000-0000-0000-000000000202','Whip Antenna 5 m','Telescopic, 5 m',100,'NO','feasible','pending'),
 ('00000000-0000-0000-0000-000000000a03','00000000-0000-0000-0000-000000000902',1,'00000000-0000-0000-0000-000000000202','Whip Antenna 5 m','Salt-spray resistant',40,'NO','clarification_needed','pending'),
 ('00000000-0000-0000-0000-000000000a04','00000000-0000-0000-0000-000000000903',1,'00000000-0000-0000-0000-000000000203','Li-Ion Battery Pack','12 V, 10 Ah',50,'NO','feasible','compliant')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Quotations (one draft, one approved with an approval step + margin data)
-- ---------------------------------------------------------------------------
insert into public.quotations (id, quotation_no, version, customer_id, tender_id, quote_date, validity_date, currency, status, notes, payment_terms, delivery_terms, warranty) values
 ('00000000-0000-0000-0000-000000000b01','QTN-0001',1,'00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000902',current_date,current_date + 30,'INR','draft','Draft quote for Navy antennas','30% advance, 70% on delivery','8-10 weeks, FOR destination','24 months'),
 ('00000000-0000-0000-0000-000000000b02','QTN-0002',1,'00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000904',current_date - 20,current_date + 10,'INR','draft','Approved quote for Army GPS','30% advance, 70% on delivery','6-8 weeks, FOR destination','24 months')
on conflict (id) do nothing;

insert into public.quotation_items
 (id, quotation_id, line_no, product_id, tender_requirement_id, source_oem_id, description, quantity, unit, unit_price, discount_pct, tax_pct, purchase_unit_cost, logistics_unit_cost, other_unit_cost, technical_compliance)
select v.id::uuid, v.quotation_id::uuid, v.line_no, v.product_id::uuid, v.tender_requirement_id::uuid, v.source_oem_id::uuid,
       v.description, v.quantity, v.unit, v.unit_price, v.discount_pct, v.tax_pct, v.purchase_unit_cost, v.logistics_unit_cost, v.other_unit_cost, v.technical_compliance
from (values
 ('00000000-0000-0000-0000-000000000c01','00000000-0000-0000-0000-000000000b01',1,'00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000a03','00000000-0000-0000-0000-000000000301','Whip Antenna 5 m',40,'NO',6000,5,18,4000,200,100,'compliant'),
 ('00000000-0000-0000-0000-000000000c02','00000000-0000-0000-0000-000000000b01',2,'00000000-0000-0000-0000-000000000203',null,'00000000-0000-0000-0000-000000000303','Li-Ion Battery Pack',20,'NO',12000,0,18,8500,300,100,'pending'),
 ('00000000-0000-0000-0000-000000000c03','00000000-0000-0000-0000-000000000b02',1,'00000000-0000-0000-0000-000000000204',null,'00000000-0000-0000-0000-000000000303','GPS Module',5,'NO',25000,0,18,18000,500,200,'partially_compliant'),
 ('00000000-0000-0000-0000-000000000c04','00000000-0000-0000-0000-000000000b02',2,'00000000-0000-0000-0000-000000000201',null,'00000000-0000-0000-0000-000000000301','VHF Radio Set',10,'NO',45000,0,18,32000,800,500,'compliant')
) as v(id, quotation_id, line_no, product_id, tender_requirement_id, source_oem_id, description, quantity, unit, unit_price, discount_pct, tax_pct, purchase_unit_cost, logistics_unit_cost, other_unit_cost, technical_compliance)
where not exists (select 1 from public.quotation_items q where q.id = v.id::uuid)
on conflict (id) do nothing;

insert into public.quotation_approvals (id, quotation_id, step_no, approver_user_id, decision, comments, decided_at) values
 ('00000000-0000-0000-0000-000000000d01','00000000-0000-0000-0000-000000000b02',1,(select id from public.users order by created_at asc limit 1),'approved','Approved - margin acceptable',now())
on conflict (id) do nothing;

-- approve QTN-0002 after its lines exist (freeze trigger blocks edits once approved)
update public.quotations
   set status = 'approved',
       approved_by = (select id from public.users order by created_at asc limit 1),
       approved_at = now()
 where id = '00000000-0000-0000-0000-000000000b02' and status = 'draft';

-- ---------------------------------------------------------------------------
-- Customer orders + lines
-- ---------------------------------------------------------------------------
insert into public.customer_orders (id, order_no, order_date, customer_id, quotation_id, currency, delivery_terms, payment_terms, consignee_name, consignee_address, status) values
 ('00000000-0000-0000-0000-000000000e01','PO-CUST-1001',current_date - 15,'00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000b02','INR','6-8 weeks','30% advance, 70% on delivery','Army Base Workshop','Pune, Maharashtra','in_procurement'),
 ('00000000-0000-0000-0000-000000000e02','PO-CUST-1002',current_date - 35,'00000000-0000-0000-0000-000000000103',null,'INR','4-6 weeks','100% on delivery','BSF Depot','Tekanpur, Madhya Pradesh','delivered')
on conflict (id) do nothing;

insert into public.order_items (id, customer_order_id, line_no, product_id, quotation_item_id, description, quantity, unit, unit_price, discount_pct, tax_pct, delivered_qty, status) values
 ('00000000-0000-0000-0000-000000000f01','00000000-0000-0000-0000-000000000e01',1,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000c03','GPS Module',5,'NO',25000,0,18,0,'open'),
 ('00000000-0000-0000-0000-000000000f02','00000000-0000-0000-0000-000000000e01',2,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000c04','VHF Radio Set',10,'NO',45000,0,18,0,'open'),
 ('00000000-0000-0000-0000-000000000f03','00000000-0000-0000-0000-000000000e02',1,'00000000-0000-0000-0000-000000000203',null,'Li-Ion Battery Pack',20,'NO',12000,0,18,20,'delivered'),
 ('00000000-0000-0000-0000-000000000f04','00000000-0000-0000-0000-000000000e02',2,'00000000-0000-0000-0000-000000000204',null,'GPS Module',5,'NO',25000,0,18,5,'delivered')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Material requirement -> purchase request -> RFQ -> OEM quotation -> PO
-- ---------------------------------------------------------------------------
insert into public.material_requirements (id, requirement_no, customer_order_id, requested_by, required_by_date, priority, status, notes) values
 ('00000000-0000-0000-0000-000000001001','MR-2026-001','00000000-0000-0000-0000-000000000e01',(select id from public.users order by created_at asc limit 1),current_date + 25,'high','ordered','Procure radios for PO-CUST-1001')
on conflict (id) do nothing;

insert into public.material_requirement_items (id, material_requirement_id, line_no, product_id, order_item_id, description, quantity, unit, required_by, status) values
 ('00000000-0000-0000-0000-000000001101','00000000-0000-0000-0000-000000001001',1,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000f02','VHF Radio Set',10,'NO',current_date + 25,'ordered'),
 ('00000000-0000-0000-0000-000000001102','00000000-0000-0000-0000-000000001001',2,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000f01','GPS Module',5,'NO',current_date + 25,'ordered')
on conflict (id) do nothing;

insert into public.purchase_requests (id, request_no, customer_order_id, requested_by, needed_by, priority, status, material_requirement_id) values
 ('00000000-0000-0000-0000-000000001201','PR-2026-001','00000000-0000-0000-0000-000000000e01',(select id from public.users order by created_at asc limit 1),current_date + 25,'high','converted','00000000-0000-0000-0000-000000001001')
on conflict (id) do nothing;

insert into public.purchase_request_items (id, purchase_request_id, line_no, product_id, description, quantity, unit, required_by, status) values
 ('00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',1,'00000000-0000-0000-0000-000000000201','VHF Radio Set',10,'NO',current_date + 25,'converted'),
 ('00000000-0000-0000-0000-000000001302','00000000-0000-0000-0000-000000001201',2,'00000000-0000-0000-0000-000000000204','GPS Module',5,'NO',current_date + 25,'converted')
on conflict (id) do nothing;

insert into public.oem_rfqs (id, rfq_no, oem_id, material_requirement_id, purchase_request_id, sent_date, due_date, currency, status) values
 ('00000000-0000-0000-0000-000000001401','RFQ-2026-001','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000001001','00000000-0000-0000-0000-000000001201',current_date - 12,current_date - 2,'INR','quotes_received'),
 ('00000000-0000-0000-0000-000000001402','RFQ-2026-001','00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000001001','00000000-0000-0000-0000-000000001201',current_date - 12,current_date - 2,'INR','closed')
on conflict (id) do nothing;

insert into public.oem_rfq_items (id, oem_rfq_id, line_no, product_id, material_requirement_item_id, description, quantity, unit) values
 ('00000000-0000-0000-0000-000000001501','00000000-0000-0000-0000-000000001401',1,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000001101','VHF Radio Set',10,'NO'),
 ('00000000-0000-0000-0000-000000001502','00000000-0000-0000-0000-000000001401',2,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000001102','GPS Module',5,'NO'),
 ('00000000-0000-0000-0000-000000001503','00000000-0000-0000-0000-000000001402',1,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000001101','VHF Radio Set',10,'NO'),
 ('00000000-0000-0000-0000-000000001504','00000000-0000-0000-0000-000000001402',2,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000001102','GPS Module',5,'NO')
on conflict (id) do nothing;

insert into public.oem_quotations (id, quotation_no, oem_id, oem_rfq_id, quote_date, validity_date, currency, payment_terms, delivery_terms, warranty, lead_time_days, status, selected_at) values
 ('00000000-0000-0000-0000-000000001601','OEMQ-2026-001','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000001401',current_date - 10,current_date + 20,'INR','30% advance, 70% on delivery','Ex-works Bengaluru','24 months',30,'selected',now()),
 ('00000000-0000-0000-0000-000000001602','OEMQ-2026-002','00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000001402',current_date - 9,current_date + 15,'INR','50% advance, 50% on delivery','FOR destination','12 months',45,'rejected',null)
on conflict (id) do nothing;

insert into public.oem_quotation_items (id, oem_quotation_id, line_no, oem_rfq_item_id, product_id, description, quantity, unit, unit_price, discount_pct, tax_pct) values
 ('00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001601',1,'00000000-0000-0000-0000-000000001501','00000000-0000-0000-0000-000000000201','VHF Radio Set',10,'NO',31500,0,18),
 ('00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000001601',2,'00000000-0000-0000-0000-000000001502','00000000-0000-0000-0000-000000000204','GPS Module',5,'NO',18500,0,18),
 ('00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000001602',1,'00000000-0000-0000-0000-000000001503','00000000-0000-0000-0000-000000000201','VHF Radio Set',10,'NO',33000,0,18)
on conflict (id) do nothing;

insert into public.purchase_orders (id, po_no, po_date, oem_id, customer_order_id, purchase_request_id, oem_quotation_id, material_requirement_id, currency, expected_delivery_date, payment_terms, warranty, status, approved_by, approved_at, terms) values
 ('00000000-0000-0000-0000-000000001801','PO-OEM-2001',current_date - 8,'00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000e01','00000000-0000-0000-0000-000000001201','00000000-0000-0000-0000-000000001601','00000000-0000-0000-0000-000000001001','INR',current_date + 20,'30% advance, 70% on delivery','24 months','approved',(select id from public.users order by created_at asc limit 1),now(),'Ex-works Bengaluru'),
 ('00000000-0000-0000-0000-000000001802','PO-OEM-2002',current_date - 14,'00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000e01',null,'00000000-0000-0000-0000-000000001602',null,'INR',current_date - 3,'50% advance, 50% on delivery','12 months','sent',null,null,'FOR destination (delayed)')
on conflict (id) do nothing;

insert into public.purchase_order_items (id, purchase_order_id, line_no, product_id, order_item_id, description, quantity, unit, unit_price, discount_pct, tax_pct, status) values
 ('00000000-0000-0000-0000-000000001901','00000000-0000-0000-0000-000000001801',1,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000f02','VHF Radio Set',10,'NO',31500,0,18,'open'),
 ('00000000-0000-0000-0000-000000001902','00000000-0000-0000-0000-000000001801',2,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000f01','GPS Module',5,'NO',18500,0,18,'open'),
 ('00000000-0000-0000-0000-000000001903','00000000-0000-0000-0000-000000001802',1,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000f02','VHF Radio Set',5,'NO',33000,0,18,'open')
on conflict (id) do nothing;

insert into public.purchase_approvals (id, purchase_order_id, step_no, approver_user_id, decision, comments, decided_at) values
 ('00000000-0000-0000-0000-000000001a01','00000000-0000-0000-0000-000000001801',1,(select id from public.users order by created_at asc limit 1),'approved','Approved - within budget',now())
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Material receipts + PDI (one passed -> ready for dispatch, one pending)
-- ---------------------------------------------------------------------------
insert into public.material_receipts (id, grn_no, purchase_order_id, oem_id, docket_no, expected_date, received_date, received_by, status, inspection_status) values
 ('00000000-0000-0000-0000-000000001b01','GRN-2026-001','00000000-0000-0000-0000-000000001801','00000000-0000-0000-0000-000000000301','LR-556677',current_date - 5,current_date - 5,(select id from public.users order by created_at asc limit 1),'received','passed'),
 ('00000000-0000-0000-0000-000000001b02','GRN-2026-002','00000000-0000-0000-0000-000000001802','00000000-0000-0000-0000-000000000302','LR-998877',current_date - 3,current_date - 2,(select id from public.users order by created_at asc limit 1),'received','pending')
on conflict (id) do nothing;

insert into public.material_receipt_items (id, material_receipt_id, purchase_order_item_id, product_id, qty_received, qty_accepted, qty_rejected) values
 ('00000000-0000-0000-0000-000000001c01','00000000-0000-0000-0000-000000001b01','00000000-0000-0000-0000-000000001901','00000000-0000-0000-0000-000000000201',10,10,0),
 ('00000000-0000-0000-0000-000000001c02','00000000-0000-0000-0000-000000001b02','00000000-0000-0000-0000-000000001903','00000000-0000-0000-0000-000000000201',5,5,0)
on conflict (id) do nothing;

insert into public.pdi_records (id, pdi_no, material_receipt_id, customer_order_id, inspection_type, inspection_date, inspector_user_id, agency, result, certificate_no) values
 ('00000000-0000-0000-0000-000000001d01','PDI-2026-001','00000000-0000-0000-0000-000000001b01','00000000-0000-0000-0000-000000000e01','pdi',current_date - 4,(select id from public.users order by created_at asc limit 1),'In-house QA','pass','PDI/CERT/001')
on conflict (id) do nothing;

insert into public.pdi_items (id, pdi_record_id, material_receipt_item_id, product_id, qty_inspected, qty_passed, qty_failed) values
 ('00000000-0000-0000-0000-000000001e01','00000000-0000-0000-0000-000000001d01','00000000-0000-0000-0000-000000001c01','00000000-0000-0000-0000-000000000201',10,10,0)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Invoices + payment (one outstanding, one overdue/part-paid)
-- ---------------------------------------------------------------------------
insert into public.invoices (id, invoice_no, invoice_date, customer_id, customer_order_id, currency, due_date, status) values
 ('00000000-0000-0000-0000-000000001f01','INV-2026-001',current_date - 10,'00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000e01','INR',current_date + 15,'issued'),
 ('00000000-0000-0000-0000-000000001f02','INV-2026-002',current_date - 30,'00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000e02','INR',current_date - 10,'issued')
on conflict (id) do nothing;

insert into public.invoice_items (id, invoice_id, line_no, product_id, order_item_id, description, quantity, unit, unit_price, discount_pct, tax_pct) values
 ('00000000-0000-0000-0000-000000002001','00000000-0000-0000-0000-000000001f01',1,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000f01','GPS Module',5,'NO',25000,0,18),
 ('00000000-0000-0000-0000-000000002002','00000000-0000-0000-0000-000000001f01',2,'00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000f02','VHF Radio Set',10,'NO',45000,0,18),
 ('00000000-0000-0000-0000-000000002003','00000000-0000-0000-0000-000000001f02',1,'00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000f03','Li-Ion Battery Pack',20,'NO',12000,0,18),
 ('00000000-0000-0000-0000-000000002004','00000000-0000-0000-0000-000000001f02',2,'00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000f04','GPS Module',5,'NO',25000,0,18)
on conflict (id) do nothing;

insert into public.payments (id, payment_no, payment_type, invoice_id, customer_id, payment_date, amount, currency, mode, reference, recorded_by) values
 ('00000000-0000-0000-0000-000000002101','PMT-2026-001','customer_receipt','00000000-0000-0000-0000-000000001f02','00000000-0000-0000-0000-000000000103',current_date - 20,100000,'INR','neft','UTR20261001',(select id from public.users order by created_at asc limit 1))
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Warranties + tasks
-- ---------------------------------------------------------------------------
insert into public.warranties (id, customer_id, customer_order_id, order_item_id, product_id, warranty_type, start_date, end_date, terms, status) values
 ('00000000-0000-0000-0000-000000002201','00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000e02','00000000-0000-0000-0000-000000000f03','00000000-0000-0000-0000-000000000203','standard',current_date - 30,current_date + 700,'24 months from delivery','active')
on conflict (id) do nothing;

insert into public.tasks (id, title, description, entity_table, entity_id, assigned_to, due_date, priority, status) values
 ('00000000-0000-0000-0000-000000002301','Follow up TND-2026-002 with Naval Dockyard','Confirm antenna specification clarification','tenders','00000000-0000-0000-0000-000000000902',(select id from public.users order by created_at asc limit 1),current_date + 3,'high','open'),
 ('00000000-0000-0000-0000-000000002302','Chase OEM delivery for PO-OEM-2002','Alpha Defence delivery is overdue - call them','purchase_orders','00000000-0000-0000-0000-000000001802',(select id from public.users order by created_at asc limit 1),current_date + 1,'critical','open')
on conflict (id) do nothing;
