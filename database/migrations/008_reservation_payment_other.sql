ALTER TABLE mat_reservations DROP CONSTRAINT mat_reservations_payment_method_check;
ALTER TABLE mat_reservations ADD CONSTRAINT mat_reservations_payment_method_check
  CHECK (payment_method IN ('deposit', 'easy', 'transfer', 'other'));
