-- =====================================================
-- COMPLETE AUTOMATED SETUP
-- Kopiere & füge diesen Code in Supabase SQL Editor ein
-- ALLES wird automatisch erstellt!
-- =====================================================

-- 1. Create tokenization_drafts table
CREATE TABLE IF NOT EXISTS public.tokenization_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_type TEXT CHECK (token_type IN ('utility', 'security')),
    current_step INTEGER DEFAULT 1,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'cancelled')),
    asset_name TEXT,
    asset_category TEXT,
    asset_description TEXT,
    asset_value DECIMAL(18, 2),
    asset_location TEXT,
    logo_url TEXT,
    header_image_url TEXT,
    token_standard TEXT,
    total_supply BIGINT,
    token_symbol TEXT,
    price_per_token DECIMAL(18, 6),
    minimum_investment DECIMAL(18, 2),
    expected_apy DECIMAL(5, 2),
    revenue_distribution TEXT CHECK (revenue_distribution IN ('monthly', 'quarterly', 'annually')),
    revenue_currency TEXT CHECK (revenue_currency IN ('USDC', 'USDT')),
    lockup_period INTEGER,
    has_spv BOOLEAN DEFAULT false,
    spv_details TEXT,
    operator TEXT CHECK (operator IN ('owner', 'third-party', 'pcx-partners')),
    management_fee DECIMAL(5, 2),
    access_rights TEXT,
    validity_period TEXT,
    is_transferable BOOLEAN DEFAULT true,
    is_burnable BOOLEAN DEFAULT false,
    jurisdiction TEXT,
    needs_audit BOOLEAN DEFAULT false,
    prospectus_document_id UUID REFERENCES public.user_documents(id),
    legal_opinion_document_id UUID REFERENCES public.user_documents(id),
    ownership_proof_document_id UUID REFERENCES public.user_documents(id),
    insurance_document_id UUID REFERENCES public.user_documents(id),
    form_data JSONB,

    -- Terms & Signature
    terms_accepted BOOLEAN DEFAULT false,
    wallet_signature TEXT,
    signature_timestamp TIMESTAMPTZ,
    signer_address TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    submitted_at TIMESTAMPTZ,
    CONSTRAINT valid_step CHECK (current_step BETWEEN 1 AND 6)
);

-- 2. Create indexes
CREATE INDEX IF NOT EXISTS idx_tokenization_drafts_user_id ON public.tokenization_drafts(user_id);
CREATE INDEX IF NOT EXISTS idx_tokenization_drafts_status ON public.tokenization_drafts(status);
CREATE INDEX IF NOT EXISTS idx_tokenization_drafts_created_at ON public.tokenization_drafts(created_at DESC);

-- 3. Create trigger for auto-update timestamp
CREATE OR REPLACE FUNCTION update_tokenization_draft_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_tokenization_draft_timestamp
    BEFORE UPDATE ON public.tokenization_drafts
    FOR EACH ROW
    EXECUTE FUNCTION update_tokenization_draft_timestamp();

-- 4. Enable RLS
ALTER TABLE public.tokenization_drafts ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS Policies for tokenization_drafts
CREATE POLICY "Users can view their own tokenization drafts"
ON public.tokenization_drafts FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can create their own tokenization drafts"
ON public.tokenization_drafts FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own tokenization drafts"
ON public.tokenization_drafts FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own tokenization drafts"
ON public.tokenization_drafts FOR DELETE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Admins can view all tokenization drafts"
ON public.tokenization_drafts FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- 6. Create helper view
CREATE OR REPLACE VIEW public.user_tokenization_assets AS
SELECT
    d.id,
    d.user_id,
    d.token_type,
    d.asset_name,
    d.asset_category,
    d.asset_value,
    d.logo_url,
    d.header_image_url,
    d.status,
    d.current_step,
    d.created_at,
    d.updated_at,
    d.submitted_at,
    u.email as user_email,
    u.name as user_name,
    CASE
        WHEN d.token_type = 'security' THEN (d.current_step::float / 6.0 * 100)::int
        WHEN d.token_type = 'utility' THEN (d.current_step::float / 5.0 * 100)::int
        ELSE 0
    END as completion_percentage
FROM public.tokenization_drafts d
JOIN public.users u ON d.user_id = u.id;

-- 7. Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tokenization_drafts TO authenticated;
GRANT SELECT ON public.user_tokenization_assets TO authenticated;

-- 8. Create Storage Buckets (via SQL)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('tokenization-images', 'tokenization-images', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/svg+xml', 'image/webp']),
  ('tokenization-documents', 'tokenization-documents', false, 52428800, ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
ON CONFLICT (id) DO NOTHING;

-- 9. Storage Policies for tokenization-images (PUBLIC bucket)
CREATE POLICY "Users can upload their own tokenization images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'tokenization-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Anyone can view tokenization images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'tokenization-images');

CREATE POLICY "Users can update their own tokenization images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'tokenization-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can delete their own tokenization images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'tokenization-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 10. Storage Policies for tokenization-documents (PRIVATE bucket)
CREATE POLICY "Users can upload their own tokenization documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'tokenization-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can read their own tokenization documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'tokenization-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Admins can read all tokenization documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'tokenization-documents'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND is_admin = true
    )
  )
);

CREATE POLICY "Users can update their own tokenization documents"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'tokenization-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can delete their own tokenization documents"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'tokenization-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- =====================================================
-- ✅ COMPLETE! ALLES FERTIG!
-- =====================================================
--
-- Was wurde erstellt:
-- ✅ tokenization_drafts Tabelle
-- ✅ Indexes für Performance
-- ✅ Auto-Update Trigger
-- ✅ RLS Policies für tokenization_drafts
-- ✅ Helper View
-- ✅ Storage Bucket: tokenization-images (Public, 10MB)
-- ✅ Storage Bucket: tokenization-documents (Private, 50MB)
-- ✅ Storage Policies für beide Buckets
-- ✅ Permissions granted
--
-- READY TO USE! 🚀
-- =====================================================
