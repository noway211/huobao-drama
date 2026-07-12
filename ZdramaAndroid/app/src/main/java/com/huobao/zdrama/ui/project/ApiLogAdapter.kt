package com.huobao.zdrama.ui.project

import androidx.core.content.ContextCompat
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.huobao.zdrama.R
import com.huobao.zdrama.data.remote.ApiLogEntry
import com.huobao.zdrama.databinding.ItemApiLogBinding
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ApiLogAdapter : RecyclerView.Adapter<ApiLogAdapter.LogViewHolder>() {
    private val entries = mutableListOf<ApiLogEntry>()
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    fun submitList(items: List<ApiLogEntry>) {
        entries.clear()
        entries.addAll(items)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LogViewHolder {
        val binding = ItemApiLogBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return LogViewHolder(binding)
    }

    override fun onBindViewHolder(holder: LogViewHolder, position: Int) {
        holder.bind(entries[position])
    }

    override fun getItemCount(): Int = entries.size

    inner class LogViewHolder(
        private val binding: ItemApiLogBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(entry: ApiLogEntry) {
            val context = binding.root.context
            val time = timeFormat.format(Date(entry.timestamp))
            val statusText = if (entry.isSuccess) {
                (entry.statusCode ?: 0).toString()
            } else {
                entry.statusCode?.toString() ?: context.getString(R.string.api_log_failed)
            }
            binding.statusText.text = "$time  ${entry.method}  $statusText  ${entry.durationMs}ms"
            binding.statusText.setTextColor(
                ContextCompat.getColor(
                    context,
                    if (entry.isSuccess) R.color.zdrama_success else R.color.zdrama_error
                )
            )
            binding.urlText.text = entry.url

            binding.requestBodyText.text = entry.requestBody?.takeIf { it.isNotBlank() } ?: "-"

            if (entry.errorMessage != null) {
                binding.responseLabelText.text = context.getString(R.string.api_log_error_label)
                binding.responseBodyText.text = entry.errorMessage
            } else {
                binding.responseLabelText.text = context.getString(R.string.api_log_response_label)
                binding.responseBodyText.text =
                    entry.responseBody?.takeIf { it.isNotBlank() } ?: "-"
            }

            val hasRequest = !entry.requestBody.isNullOrBlank()
            binding.requestLabelText.visibility = if (hasRequest) View.VISIBLE else View.GONE
            binding.requestBodyText.visibility = if (hasRequest) View.VISIBLE else View.GONE
        }
    }
}
