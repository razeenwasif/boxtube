import { useState, useEffect } from 'react'
import { useParams } from 'react-router-dom'
import { Box, Typography, Button } from '@mui/material'
import { Subscriptions } from '@mui/icons-material'

import { Videos, ChannelCard } from './'
import { fetchFromAPI } from '../utils/fetchFromAPI'
import { useAuth } from '../contexts/AuthContext'

const ChannelDetail = () => {
  const [channelDetail, setChannelDetail] = useState(null)
  const [videos, setVideos] = useState([])
  const [subscriberCount, setSubscriberCount] = useState(0)
  
  const { id } = useParams()
  const { currentUser, subscribeToChannel, isSubscribed } = useAuth()
  const [subscribed, setSubscribed] = useState(false)

  useEffect(() => {
    const fetchChannelData = async () => {
      try {
        // Fetch channel details
        const channelData = await fetchFromAPI(`channels?part=snippet,statistics&id=${id}`)
        setChannelDetail(channelData?.items[0])
        setSubscriberCount(parseInt(channelData?.items[0]?.statistics?.subscriberCount || 0))
        
        // Fetch channel videos
        const videosData = await fetchFromAPI(`search?channelId=${id}&part=snippet&order=date`)
        setVideos(videosData?.items)
      } catch (error) {
        console.error('Error fetching channel data:', error)
      }
    }

    fetchChannelData()
  }, [id])
  
  // Check if user is subscribed to this channel
  useEffect(() => {
    if (currentUser) {
      setSubscribed(isSubscribed(id))
    } else {
      setSubscribed(false)
    }
  }, [currentUser, id, isSubscribed])
  
  // Handle subscribe/unsubscribe
  const handleSubscribe = () => {
    if (!currentUser) {
      // Redirect to login or show login prompt
      return
    }
    
    const isNowSubscribed = subscribeToChannel(
      id, 
      channelDetail?.snippet?.title, 
      channelDetail?.snippet?.thumbnails?.default?.url
    )
    
    setSubscribed(isNowSubscribed)
    
    // Update local subscriber count for immediate feedback
    setSubscriberCount(prev => isNowSubscribed ? prev + 1 : Math.max(0, prev - 1))
  }
  
  // Format subscriber count
  const formatSubscriberCount = (count) => {
    if (count >= 1000000) {
      return `${(count / 1000000).toFixed(1)}M`
    } else if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}K`
    }
    return count.toString()
  }

  return (
    <Box minHeight='95vh'>
      <Box>
        <div style={{
          background: 'linear-gradient(90deg, rgba(2,0,36,1) 27%, rgba(121,9,55,1) 100%, rgba(0,212,255,1) 100%)',
          zIndex: 10,
          height: '300px'
        }} />
        
        <Box 
          sx={{ 
            display: 'flex', 
            flexDirection: { xs: 'column', md: 'row' },
            alignItems: 'center',
            justifyContent: 'center',
            mt: '-110px',
            mb: 3,
            px: 3
          }}
        >
          {/* Channel avatar and info */}
          <Box 
            sx={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center',
              mr: { md: 5 },
              mb: { xs: 3, md: 0 }
            }}
          >
            <ChannelCard channelDetail={channelDetail} />
          </Box>
          
          {/* Subscriber count and subscribe button */}
          <Box 
            sx={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: { xs: 'center', md: 'flex-start' }
            }}
          >
            <Typography 
              variant="h6" 
              sx={{ 
                color: 'var(--text-primary)',
                display: 'flex',
                alignItems: 'center',
                mb: 1
              }}
            >
              {formatSubscriberCount(subscriberCount)} subscribers
            </Typography>
            
            <Button
              variant={subscribed ? "outlined" : "contained"}
              startIcon={<Subscriptions />}
              onClick={handleSubscribe}
              sx={{
                backgroundColor: subscribed ? 'transparent' : 'var(--primary-color)',
                borderColor: subscribed ? 'var(--primary-color)' : 'transparent',
                color: subscribed ? 'var(--primary-color)' : 'white',
                '&:hover': {
                  backgroundColor: subscribed ? 'rgba(255, 0, 0, 0.08)' : 'var(--primary-color-dark)',
                  borderColor: subscribed ? 'var(--primary-color)' : 'transparent',
                }
              }}
            >
              {subscribed ? 'Subscribed' : 'Subscribe'}
            </Button>
          </Box>
        </Box>
      </Box>
      
      <Box p={2}>
        <Videos videos={videos} />
      </Box>
    </Box>
  )
}

export default ChannelDetail