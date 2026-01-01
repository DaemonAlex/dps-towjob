--[[
    dps-towjob Database Schema
    Run this SQL to create required tables
]]

-- Tow jobs table (main job tracking)
CREATE TABLE IF NOT EXISTS `tow_jobs` (
    `id` VARCHAR(20) PRIMARY KEY,
    `type` VARCHAR(20) NOT NULL COMMENT 'pve, customer, police, ems',
    `priority` INT DEFAULT 2 COMMENT '1=low, 2=normal, 3=high',
    `pickup_coords` VARCHAR(100) NOT NULL,
    `dropoff_coords` VARCHAR(100) DEFAULT NULL,
    `vehicle_plate` VARCHAR(10) DEFAULT NULL,
    `vehicle_model` VARCHAR(50) DEFAULT NULL,
    `requester_id` VARCHAR(50) DEFAULT NULL COMMENT 'citizenid of requester',
    `driver_id` VARCHAR(50) DEFAULT NULL COMMENT 'citizenid of tow driver',
    `shop_id` VARCHAR(50) DEFAULT NULL COMMENT 'Shop that driver is assigned to',
    `state` VARCHAR(20) DEFAULT 'queued' COMMENT 'queued, assigned, en_route, on_scene, towing, completed, cancelled',
    `payment` INT DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `assigned_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    INDEX `idx_state` (`state`),
    INDEX `idx_driver_id` (`driver_id`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Service tickets for repair handoffs
CREATE TABLE IF NOT EXISTS `tow_service_tickets` (
    `id` VARCHAR(20) PRIMARY KEY,
    `shop` VARCHAR(50) NOT NULL,
    `vehicle_data` LONGTEXT NOT NULL COMMENT 'JSON: plate, model, owner',
    `customer_data` LONGTEXT NOT NULL COMMENT 'JSON: source, citizenid',
    `status` ENUM('awaiting_repair', 'in_progress', 'completed', 'cancelled') DEFAULT 'awaiting_repair',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL,
    `towed_by` VARCHAR(50) NOT NULL COMMENT 'citizenid of tow driver',
    `repaired_by` VARCHAR(50) NULL COMMENT 'citizenid of mechanic',
    `repair_cost` INT DEFAULT 0,
    INDEX `idx_shop` (`shop`),
    INDEX `idx_status` (`status`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shop transaction log
CREATE TABLE IF NOT EXISTS `tow_shop_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop` VARCHAR(50) NOT NULL,
    `amount` INT NOT NULL,
    `type` ENUM('tow_payment', 'impound_fee', 'withdrawal', 'repair_handoff') NOT NULL,
    `description` VARCHAR(255) DEFAULT NULL,
    `citizenid` VARCHAR(50) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_shop` (`shop`),
    INDEX `idx_type` (`type`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Driver earnings tracking
CREATE TABLE IF NOT EXISTS `tow_driver_earnings` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `shop` VARCHAR(50) NOT NULL COMMENT 'Last shop worked at',
    `total_earned` INT DEFAULT 0,
    `uncollected` INT DEFAULT 0 COMMENT 'Amount waiting to be collected',
    `total_jobs` INT DEFAULT 0,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_shop` (`shop`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Impound tracking (links to player_vehicles)
CREATE TABLE IF NOT EXISTS `tow_impound_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `plate` VARCHAR(10) NOT NULL,
    `impound_lot` VARCHAR(50) NOT NULL,
    `towed_by` VARCHAR(50) NOT NULL COMMENT 'citizenid of tow driver',
    `reason` VARCHAR(255) DEFAULT NULL,
    `fee` INT DEFAULT 0,
    `impounded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `released_at` TIMESTAMP NULL,
    `released_by` VARCHAR(50) NULL,
    INDEX `idx_plate` (`plate`),
    INDEX `idx_impound_lot` (`impound_lot`),
    INDEX `idx_impounded_at` (`impounded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Driver stats for leaderboard/metrics
CREATE TABLE IF NOT EXISTS `tow_driver_stats` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `total_jobs_completed` INT DEFAULT 0,
    `total_miles_driven` FLOAT DEFAULT 0,
    `total_earned` INT DEFAULT 0,
    `pve_jobs` INT DEFAULT 0,
    `customer_jobs` INT DEFAULT 0,
    `police_jobs` INT DEFAULT 0,
    `ems_jobs` INT DEFAULT 0,
    `average_completion_time` INT DEFAULT 0 COMMENT 'In seconds',
    `fastest_completion` INT DEFAULT 0 COMMENT 'In seconds',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
