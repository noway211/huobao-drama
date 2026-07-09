package com.huobao.zdrama.ui.main

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.huobao.zdrama.databinding.ActivityMainBinding
import com.huobao.zdrama.ui.create.CreateProjectActivity
import com.huobao.zdrama.ui.project.ProjectListActivity
import com.huobao.zdrama.ui.settings.SettingsActivity

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.settingsButton.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        binding.createButton.setOnClickListener {
            startActivity(Intent(this, CreateProjectActivity::class.java))
        }
        binding.projectsButton.setOnClickListener {
            startActivity(Intent(this, ProjectListActivity::class.java))
        }
    }
}
