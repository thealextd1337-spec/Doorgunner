class_name OnlineConfig
extends RefCounted
## Public connection data of the Supabase project (server/README.md). Both values are meant to be public:
## the protection comes from RLS and the RPCs in server/supabase/. NEVER put the service_role key or any other secret here.

const URL := "https://yucfmsvivvoufvodeyvc.supabase.co"
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1Y2Ztc3ZpdnZvdWZ2b2RleXZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyOTc4OTIsImV4cCI6MjEwODg3Mzg5Mn0.Ohq0jDc4v2bjgN1NGjVC453WyKeP_y-bnzQr5fP4WHc"
