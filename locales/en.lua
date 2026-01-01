--[[
    dps-towjob Locales: English
]]

Locales = {
    -- General
    ['tow_job'] = 'Tow Job',
    ['tow_service'] = 'Tow Service',

    -- Duty
    ['clock_in'] = 'Clock In',
    ['clock_out'] = 'Clock Out',
    ['on_duty'] = 'You are now on duty',
    ['off_duty'] = 'You are now off duty',
    ['clocked_in_at'] = 'Clocked in at %s',
    ['complete_job_first'] = 'Complete your current job first',
    ['not_tow_driver'] = 'You are not a tow driver',
    ['must_be_on_duty'] = 'You must be on duty',

    -- Vehicle
    ['get_vehicle'] = 'Get Tow Vehicle',
    ['return_vehicle'] = 'Return Vehicle',
    ['vehicle_ready'] = 'Vehicle ready',
    ['vehicle_returned'] = 'Vehicle returned',
    ['spawn_blocked'] = 'Spawn point blocked',
    ['return_current_first'] = 'Return your current vehicle first',
    ['not_tow_vehicle'] = 'This is not a tow vehicle',
    ['no_vehicles_available'] = 'No vehicles available for your grade',

    -- Towing
    ['attach_vehicle'] = 'Attach to Tow Truck',
    ['detach_vehicle'] = 'Detach Vehicle',
    ['vehicle_attached'] = 'Vehicle attached',
    ['vehicle_detached'] = 'Vehicle detached',
    ['already_attached'] = 'Already have a vehicle attached',
    ['no_vehicle_attached'] = 'No vehicle attached',
    ['move_closer'] = 'Move closer to the vehicle',
    ['detach_first'] = 'Detach the vehicle first',
    ['vehicle_detached_distance'] = 'Vehicle detached due to distance',
    ['slow_down_warning'] = 'Slow down! Vehicle may detach',
    ['attaching'] = 'Attaching vehicle...',
    ['detaching'] = 'Detaching vehicle...',

    -- Jobs
    ['new_tow_request'] = 'New Tow Request',
    ['tow_request'] = 'Tow Request',
    ['accept_job'] = 'Accept Job',
    ['cancel_job'] = 'Cancel Job',
    ['view_details'] = 'View Details',
    ['job_accepted'] = 'Job accepted',
    ['job_cancelled'] = 'Job cancelled and requeued',
    ['job_complete'] = 'Job Complete',
    ['invalid_job'] = 'Invalid job',
    ['waiting_for_job'] = 'Waiting for Job',
    ['in_queue'] = 'You are in the queue',
    ['driver_en_route'] = 'Driver %s is en route',

    -- Destinations
    ['destination_set'] = 'Destination Set',
    ['deliver_to'] = 'Deliver to %s',
    ['drop_off_vehicle'] = 'Drop Off Vehicle',
    ['impound_vehicle'] = 'Impound Vehicle',

    -- Payment
    ['earnings'] = 'Earnings',
    ['your_earnings'] = 'Your Earnings',
    ['total_earned'] = 'Total Earned',
    ['uncollected'] = 'Uncollected',
    ['total_jobs'] = 'Total Jobs',
    ['collect_earnings'] = 'Collect Earnings',
    ['earnings_collected'] = 'Earnings Collected',
    ['deposited_to_bank'] = '%s deposited to bank',
    ['no_uncollected'] = 'No uncollected earnings',

    -- Roadside
    ['roadside_services'] = 'Roadside Services',
    ['service_complete'] = 'Service Complete',
    ['service_cancelled'] = 'Roadside service aborted',
    ['damage_too_severe'] = 'Vehicle damage too severe - must be towed to shop',
    ['tow_to_shop'] = 'Tow to Shop',
    ['attach_and_tow'] = 'Attach and tow for repairs',

    -- Queue
    ['queue_status'] = 'Queue Status',
    ['jobs_waiting'] = 'Jobs waiting',
    ['available_drivers'] = 'Available drivers',
    ['your_status'] = 'Your Status',
    ['state'] = 'State',
    ['shop'] = 'Shop',
    ['no_drivers_available'] = 'No drivers available',
    ['tow_requested'] = 'A tow driver will be dispatched shortly',
    ['tow_request_failed'] = 'Unable to request tow at this time',
    ['queue_full'] = 'Queue full',

    -- Impound
    ['impound'] = 'Impound',
    ['impound_fee'] = 'Impound Fee',
    ['vehicle_released'] = 'Vehicle released',
    ['vehicle_not_found'] = 'Vehicle not found in impound',
    ['not_enough_money'] = 'Not enough money. Fee: %s',

    -- Billing
    ['bill_sent'] = 'Bill Sent',
    ['billed_for'] = 'Billed %s for %s',
    ['invoice_received'] = 'Invoice Received',

    -- Errors
    ['error'] = 'Error',
    ['invalid_shop'] = 'Invalid shop location',
    ['player_not_found'] = 'Player not found',
    ['insufficient_funds'] = 'Insufficient funds',
    ['failed_collect'] = 'Failed to collect earnings',

    -- Job Types
    ['type_pve'] = 'PVE',
    ['type_customer'] = 'Customer',
    ['type_police'] = 'Police',
    ['type_ems'] = 'EMS',

    -- Priority
    ['priority_high'] = 'HIGH',
    ['priority_normal'] = 'NORMAL',
    ['priority_low'] = 'LOW',

    -- Menu
    ['tow_driver_menu'] = 'Tow Driver Menu',
    ['current_job'] = 'Current Job',
    ['view_active_job'] = 'View active job details',
    ['start_route'] = 'Start Route',
    ['begin_en_route'] = 'Begin en route to pickup',
    ['return_to_queue'] = 'Return job to queue',
    ['go_off_duty'] = 'Go Off Duty',
    ['end_shift'] = 'End your shift',
    ['check_uncollected'] = 'Check uncollected pay',
    ['withdraw_to_bank'] = 'Withdraw to bank',
}

-- Helper function to get locale string with formatting
function L(key, ...)
    local str = Locales[key]
    if not str then
        return 'MISSING: ' .. key
    end

    local args = {...}
    if #args > 0 then
        return string.format(str, ...)
    end

    return str
end
