import { test, expect } from '@playwright/test'

const AGNES_API_KEY = process.env.AGNES_API_KEY || ''
const API_BASE = 'http://localhost:5679/api/v1'

test.describe('Agnes AI Provider', () => {
  test('backend registry has agnesai image and video adapters', async ({ request }) => {
    // Verify we can create an agnesai config and it gets accepted
    const configRes = await request.post(`${API_BASE}/ai-configs`, {
      data: {
        name: 'AgnesAI Video E2E',
        provider: 'agnesai',
        base_url: 'https://apihub.agnes-ai.com',
        api_key: AGNES_API_KEY,
        model: ['agnes-video-v2.0'],
        service_type: 'video',
        priority: 999,
        is_active: true,
      },
    })

    const configJson = await configRes.json()
    console.log('Config creation:', configRes.status(), configJson.message || '')
    expect([200, 201, 409]).toContain(configRes.status())

    // Verify the config is listed under agnesai provider
    const listRes = await request.get(`${API_BASE}/ai-configs?service_type=video`)
    const listJson = await listRes.json()
    const agnesaiConfigs = listJson.data?.filter((c: any) => c.provider === 'agnesai')
    expect(agnesaiConfigs?.length).toBeGreaterThan(0)
  })

  test('backend video adapter generates task and polls correctly', async ({ request }) => {
    test.setTimeout(120_000) // 2 minutes

    // Step 1: Create video config
    const vidCfgRes = await request.post(`${API_BASE}/ai-configs`, {
      data: {
        name: 'E2E Video',
        provider: 'agnesai',
        base_url: 'https://apihub.agnes-ai.com',
        api_key: AGNES_API_KEY,
        model: ['agnes-video-v2.0'],
        service_type: 'video',
        priority: 999,
        is_active: true,
      },
    })
    const vidCfgJson = await vidCfgRes.json()
    const vidCfgId = vidCfgJson.data?.id

    // Step 2: Create drama + episode + storyboard
    const dramaRes = await request.post(`${API_BASE}/dramas`, {
      data: { title: 'E2E Test Drama', description: 'Playwright test', raw_content: 'test' },
    })
    const dramaJson = await dramaRes.json()
    const dramaId = dramaJson.data?.id

    const epRes = await request.post(`${API_BASE}/episodes`, {
      data: {
        drama_id: dramaId,
        title: 'Test Episode',
        image_config_id: vidCfgId,
        video_config_id: vidCfgId,
        audio_config_id: vidCfgId,
      },
    })
    const epJson = await epRes.json()
    const epId = epJson.data?.id

    const sbRes = await request.post(`${API_BASE}/storyboards`, {
      data: {
        episode_id: epId,
        storyboard_number: 1,
        title: 'Test Shot',
        description: 'A test shot for Agnes AI video generation',
        duration: 5,
        video_prompt: 'A serene landscape with mountains and a river, cinematic lighting',
      },
    })
    const sbJson = await sbRes.json()
    const sbId = sbJson.data?.id

    // Step 3: Generate video
    const videoRes = await request.post(`${API_BASE}/videos`, {
      data: {
        storyboard_id: sbId,
        drama_id: dramaId,
        prompt: 'A serene landscape with mountains and a river, cinematic lighting',
        duration: 5,
        config_id: vidCfgId,
      },
    })

    const videoJson = await videoRes.json()
    console.log('Video generation response:', videoRes.status(), JSON.stringify(videoJson))
    expect(videoRes.status()).toBe(201)
    expect(videoJson.data?.status).toBe('processing')
    expect(videoJson.data?.provider).toBe('agnesai')

    const generationId = videoJson.data?.id
    console.log('Video generation started:', generationId, 'taskId:', videoJson.data?.taskId || videoJson.data?.task_id)

    // Step 4: Poll for a few cycles and verify status transitions correctly
    let seenProcessing = false
    for (let i = 0; i < 6; i++) {
      await new Promise(r => setTimeout(r, 10000))
      const pollRes = await request.get(`${API_BASE}/videos/${generationId}`)
      const pollJson = await pollRes.json()
      console.log(`Poll ${i + 1}:`, pollJson.data?.status)

      if (pollJson.data?.status === 'processing') {
        seenProcessing = true
      }
      if (pollJson.data?.status === 'completed') {
        expect(pollJson.data?.video_url).toBeTruthy()
        return
      }
      if (pollJson.data?.status === 'failed') {
        throw new Error(`Video generation failed: ${pollJson.data?.error_msg}`)
      }
    }

    // If Agnes AI is still queued/processing after 1 min, that's expected —
    // the adapter and polling pipeline are working correctly.
    expect(seenProcessing).toBe(true)
  })

  test('backend video adapter completes end-to-end (long)', async ({ request }) => {
    test.setTimeout(600_000) // 10 minutes for full video generation

    // Find existing agnesai config or create one
    const listRes = await request.get(`${API_BASE}/ai-configs?service_type=video`)
    const listJson = await listRes.json()
    let vidCfgId = listJson.data?.find((c: any) => c.provider === 'agnesai')?.id

    if (!vidCfgId) {
      const cfgRes = await request.post(`${API_BASE}/ai-configs`, {
        data: {
          name: 'AgnesAI Video',
          provider: 'agnesai',
          base_url: 'https://apihub.agnes-ai.com',
          api_key: AGNES_API_KEY,
          model: ['agnes-video-v2.0'],
          service_type: 'video',
          priority: 999,
          is_active: true,
        },
      })
      vidCfgId = (await cfgRes.json()).data?.id
    }

    // Create minimal drama/episode/storyboard
    const dramaRes = await request.post(`${API_BASE}/dramas`, {
      data: { title: 'E2E Full Test', description: 'test', raw_content: 'test' },
    })
    const dramaId = (await dramaRes.json()).data?.id

    const epRes = await request.post(`${API_BASE}/episodes`, {
      data: { drama_id: dramaId, title: 'EP1', image_config_id: vidCfgId, video_config_id: vidCfgId, audio_config_id: vidCfgId },
    })
    const epId = (await epRes.json()).data?.id

    const sbRes = await request.post(`${API_BASE}/storyboards`, {
      data: { episode_id: epId, storyboard_number: 1, title: 'Shot', description: 'test', duration: 5, video_prompt: 'sunset over ocean' },
    })
    const sbId = (await sbRes.json()).data?.id

    // Generate video
    const videoRes = await request.post(`${API_BASE}/videos`, {
      data: { storyboard_id: sbId, drama_id: dramaId, prompt: 'sunset over ocean', duration: 5, config_id: vidCfgId },
    })
    const videoJson = await videoRes.json()
    const generationId = videoJson.data?.id
    console.log('Full E2E generation started:', generationId)

    // Poll up to 10 minutes
    let completed = false
    for (let i = 0; i < 60; i++) {
      await new Promise(r => setTimeout(r, 10000))
      const pollRes = await request.get(`${API_BASE}/videos/${generationId}`)
      const pollJson = await pollRes.json()
      console.log(`Full E2E Poll ${i + 1}:`, pollJson.data?.status)

      if (pollJson.data?.status === 'completed') {
        completed = true
        expect(pollJson.data?.video_url).toBeTruthy()
        break
      }
      if (pollJson.data?.status === 'failed') {
        throw new Error(`Video generation failed: ${pollJson.data?.error_msg}`)
      }
    }

    expect(completed).toBe(true)
  })
})