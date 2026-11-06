package com.univapayment.merchant

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result = try {
        ApiClient.sync(applicationContext)
        Result.success()
    } catch (e: ApiException) {
        // A revoked device or bad request will not fix itself by retrying.
        if (e.status >= 500 || e.status == 429) Result.retry() else Result.failure()
    } catch (e: Exception) {
        Result.retry()
    }

    companion object {
        private val online = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        /** Retries with backoff as soon as there is a network. */
        fun enqueueNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(online)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork("sync_now", ExistingWorkPolicy.REPLACE, request)
        }

        /** Heartbeat and catch-up. Survives reboots; 15 minutes is Android's shortest period. */
        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(online)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "sync_periodic", ExistingPeriodicWorkPolicy.KEEP, request,
            )
        }

        fun cancelAll(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork("sync_now")
            WorkManager.getInstance(context).cancelUniqueWork("sync_periodic")
        }
    }
}
