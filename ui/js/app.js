/**
 * DPS Tow Dispatch - Main Application
 */

const DispatchUI = {
    isOpen: false,
    selectedJob: null,

    // Data
    queue: [],
    activeJobs: [],
    drivers: [],
    stats: {
        completed: 0,
        earnings: 0,
        pve: 0,
        impound: 0
    },
    playerData: {
        onDuty: false,
        shop: null
    },

    init: function() {
        console.log('[DPS-TowJob] Dispatch UI initialized');
        this.hide();
    },

    open: function(data) {
        if (data) {
            this.queue = data.queue || [];
            this.activeJobs = data.activeJobs || [];
            this.drivers = data.drivers || [];
            this.stats = data.stats || this.stats;
            this.playerData = data.playerData || this.playerData;
        }

        this.isOpen = true;
        this.updateAll();

        const app = document.getElementById('dispatch-app');
        app.classList.remove('hidden');
    },

    close: function() {
        this.isOpen = false;
        this.closeModal();
        document.getElementById('dispatch-app').classList.add('hidden');
        Utils.nuiCallback('close');
    },

    hide: function() {
        document.getElementById('dispatch-app').classList.add('hidden');
        document.getElementById('job-modal').classList.add('hidden');
    },

    updateAll: function() {
        this.updateDutyStatus();
        this.updateStats();
        this.renderQueue();
        this.renderActiveJobs();
        this.renderDrivers();
    },

    updateDutyStatus: function() {
        const badge = document.getElementById('duty-badge');
        const status = document.getElementById('duty-status');

        if (this.playerData.onDuty) {
            badge.classList.remove('off-duty');
            status.textContent = 'On Duty';
        } else {
            badge.classList.add('off-duty');
            status.textContent = 'Off Duty';
        }
    },

    updateStats: function() {
        document.getElementById('driver-count').textContent = this.drivers.filter(d => d.state === 'available').length;
        document.getElementById('queue-count').textContent = this.queue.length;
        document.getElementById('stat-completed').textContent = this.stats.completed;
        document.getElementById('stat-earnings').textContent = Utils.formatMoney(this.stats.earnings);
        document.getElementById('stat-pve').textContent = this.stats.pve;
        document.getElementById('stat-impound').textContent = this.stats.impound;
    },

    renderQueue: function() {
        const container = document.getElementById('queue-list');
        const emptyState = document.getElementById('empty-queue');

        if (!this.queue.length) {
            container.innerHTML = '';
            emptyState.classList.remove('hidden');
            return;
        }

        emptyState.classList.add('hidden');
        container.innerHTML = this.queue.map(job => this.createQueueItem(job)).join('');
    },

    createQueueItem: function(job) {
        const typeClass = job.type || 'customer';
        const priorityClass = Utils.getPriorityClass(job.priority);
        const priorityLabel = Utils.getPriorityLabel(job.priority);

        return `
            <div class="queue-item" onclick="DispatchUI.selectJob('${job.id}')">
                <div class="queue-item-header">
                    <div class="job-type ${typeClass}">
                        <i class="${Utils.getJobTypeIcon(job.type)}"></i>
                        <span>${Utils.getJobTypeLabel(job.type)}</span>
                    </div>
                    <span class="priority-badge ${priorityClass}">${priorityLabel}</span>
                </div>
                <div class="queue-item-body">
                    <div class="job-location">
                        <i class="fas fa-map-marker-alt"></i>
                        <span>${Utils.escapeHtml(job.zone || 'Unknown Location')}</span>
                    </div>
                    ${job.vehiclePlate ? `
                    <div class="job-vehicle">
                        <i class="fas fa-car"></i>
                        <span>${Utils.escapeHtml(job.vehicleModel || 'Unknown')} [${Utils.escapeHtml(job.vehiclePlate)}]</span>
                    </div>
                    ` : ''}
                    <div class="job-time">
                        <i class="fas fa-clock"></i>
                        <span>Waiting: ${Utils.formatWaitTime(job.createdAt)}</span>
                    </div>
                </div>
            </div>
        `;
    },

    renderActiveJobs: function() {
        const container = document.getElementById('active-list');
        const emptyState = document.getElementById('empty-active');

        if (!this.activeJobs.length) {
            container.innerHTML = '';
            emptyState.classList.remove('hidden');
            return;
        }

        emptyState.classList.add('hidden');
        container.innerHTML = this.activeJobs.map(job => this.createActiveItem(job)).join('');
    },

    createActiveItem: function(job) {
        const stateClass = Utils.getStateClass(job.state);
        const stateLabel = Utils.getStateLabel(job.state);
        const progress = job.progress || 0;

        return `
            <div class="active-item">
                <div class="active-item-header">
                    <span class="driver-name">${Utils.escapeHtml(job.driverName || 'Unknown')}</span>
                    <span class="job-state ${stateClass}">${stateLabel}</span>
                </div>
                <div class="active-item-body">
                    <div class="job-location">
                        <i class="fas fa-map-marker-alt"></i>
                        <span>${Utils.escapeHtml(job.zone || 'Unknown')}</span>
                    </div>
                    ${job.vehiclePlate ? `
                    <div class="job-vehicle">
                        <i class="fas fa-car"></i>
                        <span>${Utils.escapeHtml(job.vehiclePlate)}</span>
                    </div>
                    ` : ''}
                    <div class="progress-row">
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${progress}%"></div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    },

    renderDrivers: function() {
        const container = document.getElementById('driver-list');
        const emptyState = document.getElementById('empty-drivers');

        if (!this.drivers.length) {
            container.innerHTML = '';
            emptyState.classList.remove('hidden');
            return;
        }

        emptyState.classList.add('hidden');
        container.innerHTML = this.drivers.map(driver => this.createDriverItem(driver)).join('');
    },

    createDriverItem: function(driver) {
        const initial = (driver.name || 'U')[0].toUpperCase();
        const statusClass = driver.state === 'available' ? 'available' : 'busy';
        const statusLabel = driver.state === 'available' ? 'Available' : 'Busy';

        return `
            <div class="driver-item">
                <div class="driver-avatar">${initial}</div>
                <div class="driver-info">
                    <span class="name">${Utils.escapeHtml(driver.name || 'Unknown')}</span>
                    <span class="shop">${Utils.escapeHtml(driver.shop || 'No Shop')}</span>
                </div>
                <span class="driver-status ${statusClass}">${statusLabel}</span>
            </div>
        `;
    },

    selectJob: function(jobId) {
        this.selectedJob = this.queue.find(j => j.id === jobId);
        if (!this.selectedJob) return;

        // Populate modal
        document.getElementById('modal-title').textContent = Utils.getJobTypeLabel(this.selectedJob.type);
        document.getElementById('modal-type').textContent = Utils.getJobTypeLabel(this.selectedJob.type);
        document.getElementById('modal-priority').textContent = Utils.getPriorityLabel(this.selectedJob.priority);
        document.getElementById('modal-location').textContent = this.selectedJob.zone || 'Unknown';
        document.getElementById('modal-vehicle').textContent = this.selectedJob.vehicleModel || 'Unknown';
        document.getElementById('modal-plate').textContent = this.selectedJob.vehiclePlate || 'N/A';
        document.getElementById('modal-wait').textContent = Utils.formatWaitTime(this.selectedJob.createdAt);

        document.getElementById('job-modal').classList.remove('hidden');
    },

    closeModal: function() {
        document.getElementById('job-modal').classList.add('hidden');
        this.selectedJob = null;
    },

    acceptJob: function() {
        if (!this.selectedJob) return;

        Utils.nuiCallback('acceptJob', { jobId: this.selectedJob.id });
        this.closeModal();
        this.showToast('Job accepted!', 'success');
    },

    viewOnMap: function() {
        if (!this.selectedJob) return;

        Utils.nuiCallback('viewOnMap', { jobId: this.selectedJob.id });
        this.close();
    },

    refreshQueue: function() {
        Utils.nuiCallback('refresh');
    },

    showToast: function(message, type) {
        const container = document.getElementById('toast-container');
        const toast = document.createElement('div');
        toast.className = 'toast toast-' + type;

        const icons = {
            success: 'fa-check-circle',
            error: 'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle'
        };

        toast.innerHTML = `
            <i class="fas ${icons[type] || icons.info}"></i>
            <span>${Utils.escapeHtml(message)}</span>
        `;

        container.appendChild(toast);

        setTimeout(() => {
            toast.style.animation = 'fadeOut 0.3s ease forwards';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }
};

// NUI Message Handler
window.addEventListener('message', function(event) {
    const data = event.data;

    switch (data.action) {
        case 'open':
            DispatchUI.open(data);
            break;

        case 'close':
            DispatchUI.hide();
            break;

        case 'updateQueue':
            DispatchUI.queue = data.queue || [];
            DispatchUI.renderQueue();
            DispatchUI.updateStats();
            break;

        case 'updateActiveJobs':
            DispatchUI.activeJobs = data.activeJobs || [];
            DispatchUI.renderActiveJobs();
            break;

        case 'updateDrivers':
            DispatchUI.drivers = data.drivers || [];
            DispatchUI.renderDrivers();
            DispatchUI.updateStats();
            break;

        case 'updateStats':
            DispatchUI.stats = data.stats || DispatchUI.stats;
            DispatchUI.updateStats();
            break;

        case 'jobAssigned':
            DispatchUI.showToast('New job assigned!', 'info');
            break;

        case 'jobCompleted':
            DispatchUI.showToast('Job completed! +' + Utils.formatMoney(data.payment), 'success');
            break;

        case 'toast':
            DispatchUI.showToast(data.message, data.type);
            break;

        case 'refresh':
            DispatchUI.queue = data.queue || DispatchUI.queue;
            DispatchUI.activeJobs = data.activeJobs || DispatchUI.activeJobs;
            DispatchUI.drivers = data.drivers || DispatchUI.drivers;
            DispatchUI.stats = data.stats || DispatchUI.stats;
            DispatchUI.updateAll();
            break;
    }
});

// Escape key handler
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && DispatchUI.isOpen) {
        DispatchUI.close();
    }
});

// Initialize on load
document.addEventListener('DOMContentLoaded', function() {
    DispatchUI.init();
});

window.DispatchUI = DispatchUI;
