import { useState } from 'react';
import { Box, Stack, Typography, Container } from '@mui/material';
import { SideBar, Videos } from './';
import useYoutubeApi from '../hooks/useYoutubeApi';

// This is the Side Bar and its categories

const Feed = () => {
  const [selectedCategory, setSelectedCategory] = useState('New');
  const { 
    data: videos, 
    loading, 
    error, 
    hasMore, 
    fetchMoreData 
  } = useYoutubeApi(
    'search',
    {
      part: 'snippet',
      q: selectedCategory,
      maxResults: 20 // Smaller batch size for smoother infinite scroll
    }
  );

  return (
    <Container 
      maxWidth="xl" 
      disableGutters
      sx={{
        background: 'var(--background-color)',
        minHeight: '100vh',
      }}
    >
      <Stack 
        sx={{ 
          flexDirection: { xs: "column", md: "row" },
          gap: 2,
          padding: { xs: 1, sm: 2 },
        }}
      > 
        <Box 
          sx={{ 
            height: { xs: 'auto', md: '92vh' }, 
            width: { xs: '100%', md: '240px' },
            position: { xs: 'static', md: 'sticky' },
            top: { md: '70px' },
          }}
        > 
          <SideBar 
            selectedCategory={selectedCategory}
            setSelectedCategory={setSelectedCategory}
          />
          
          <Typography 
            className='copyright' 
            variant='caption' 
            sx={{ 
              mt: 2, 
              color: 'var(--text-secondary)',
              display: 'block',
              textAlign: 'center',
              padding: '0 16px'
            }}
          > 
            © 2023 BoxTube
          </Typography>
        </Box>

        <Box 
          sx={{ 
            height: '90vh',
            flex: 1,
            borderRadius: '12px',
            background: 'var(--secondary-bg)',
            backdropFilter: 'blur(5px)',
            border: '1px solid var(--border-color)',
          }}
        >
          <Box p={3}>
            <Typography 
              variant='h5' 
              fontWeight="500" 
              sx={{ 
                color: 'var(--text-primary)',
                borderBottom: '1px solid var(--border-color)',
                paddingBottom: '12px',
              }}
            >
              {selectedCategory} <span style={{ color: 'var(--primary-color)' }}>videos</span>
            </Typography>
          </Box>

          {error ? (
            <Typography 
              variant="body1" 
              sx={{ 
                color: 'var(--text-secondary)',
                textAlign: 'center',
                mt: 4
              }}
            >
              {error}
            </Typography>
          ) : (
            <Videos 
              videos={videos}
              loading={loading}
              hasMore={hasMore}
              onLoadMore={fetchMoreData}
            />
          )}
        </Box>
      </Stack>
    </Container>
  );
};

export default Feed;