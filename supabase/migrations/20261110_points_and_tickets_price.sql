-- Migration: 20261110_points_and_tickets_price.sql
-- Description: Adds ticket_price to events and price_paid to tickets for point-based ticketing

-- Add ticket_price to events if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'events'
          AND column_name = 'ticket_price'
    ) THEN
        ALTER TABLE public.events
        ADD COLUMN ticket_price integer DEFAULT 0 CHECK (ticket_price >= 0);
        
        COMMENT ON COLUMN public.events.ticket_price IS 'Ticket price in points for attendees to purchase or redeem';
    END IF;
END $$;

-- Add price_paid to tickets if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'tickets'
          AND column_name = 'price_paid'
    ) THEN
        ALTER TABLE public.tickets
        ADD COLUMN price_paid integer DEFAULT 0 CHECK (price_paid >= 0);
        
        COMMENT ON COLUMN public.tickets.price_paid IS 'Amount of points deducted/paid for this ticket';
    END IF;
END $$;

