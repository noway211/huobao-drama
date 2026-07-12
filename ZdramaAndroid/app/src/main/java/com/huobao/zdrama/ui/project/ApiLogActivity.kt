package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.remote.ApiLogStore
import com.huobao.zdrama.databinding.ActivityApiLogBinding

class ApiLogActivity : AppCompatActivity() {
    private lateinit var binding: ActivityApiLogBinding
    private val adapter = ApiLogAdapter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityApiLogBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.logList.layoutManager = LinearLayoutManager(this)
        binding.logList.adapter = adapter
        binding.clearButton.setOnClickListener {
            ApiLogStore.clear()
            refresh()
            Toast.makeText(this, R.string.api_log_cleared, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val entries = ApiLogStore.snapshot()
        adapter.submitList(entries)
        binding.emptyText.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE
    }
}
