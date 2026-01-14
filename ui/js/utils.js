/**
 * DPS Tow Dispatch - Utility Functions
 */

const Utils = {
    formatMoney: function(amount) {
        return '$' + (amount || 0).toLocaleString('en-US');
    },

    formatTimeAgo: function(timestamp) {
        const now = Math.floor(Date.now() / 1000);
        const diff = now - timestamp;

        if (diff < 60) return 'Just now';
        if (diff < 3600) return Math.floor(diff / 60) + ' min ago';
        if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
        return Math.floor(diff / 86400) + 'd ago';
    },

    formatWaitTime: function(timestamp) {
        const now = Math.floor(Date.now() / 1000);
        const diff = now - timestamp;

        if (diff < 60) return diff + 's';
        if (diff < 3600) return Math.floor(diff / 60) + 'm ' + (diff % 60) + 's';
        return Math.floor(diff / 3600) + 'h ' + Math.floor((diff % 3600) / 60) + 'm';
    },

    getJobTypeIcon: function(type) {
        const icons = {
            'police': 'fa-shield-halved',
            'ems': 'fa-ambulance',
            'customer': 'fa-user',
            'pve': 'fa-car-burst',
            'predatory': 'fa-parking'
        };
        return 'fas ' + (icons[type] || 'fa-truck');
    },

    getJobTypeLabel: function(type) {
        const labels = {
            'police': 'Police Impound',
            'ems': 'EMS Request',
            'customer': 'Customer Tow',
            'pve': 'NPC Breakdown',
            'predatory': 'Illegal Parking'
        };
        return labels[type] || 'Tow Request';
    },

    getPriorityClass: function(priority) {
        if (priority >= 2) return 'priority-high';
        if (priority >= 1) return 'priority-normal';
        return 'priority-low';
    },

    getPriorityLabel: function(priority) {
        if (priority >= 2) return 'HIGH';
        if (priority >= 1) return 'NORMAL';
        return 'LOW';
    },

    getStateClass: function(state) {
        const classes = {
            'en_route': 'en-route',
            'on_scene': 'on-scene',
            'towing': 'towing'
        };
        return classes[state] || state;
    },

    getStateLabel: function(state) {
        const labels = {
            'en_route': 'En Route',
            'on_scene': 'On Scene',
            'towing': 'Towing'
        };
        return labels[state] || state;
    },

    nuiCallback: async function(event, data = {}) {
        try {
            const response = await fetch(`https://dps-towjob/${event}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });
            return await response.json();
        } catch (error) {
            console.error('NUI Callback Error:', error);
            return null;
        }
    },

    escapeHtml: function(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    },

    truncate: function(str, len) {
        if (!str) return '';
        return str.length > len ? str.substring(0, len) + '...' : str;
    }
};

window.Utils = Utils;
