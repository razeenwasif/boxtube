import { Link } from 'react-router-dom';
import { Typography, Card, CardContent, CardMedia, Box } from '@mui/material';
import { CheckCircle, Visibility } from '@mui/icons-material';
import {
    demoThumbnailUrl, demoVideoUrl, demoVideoTitle,
    demoChannelUrl, demoChannelTitle
} from '../utils/constants';
import useWatchHistory from '../hooks/useWatchHistory';

const VideoCard = ({ video }) => {
    const { id: { videoId }, snippet, contentDetails, statistics } = video;
    const { isWatched } = useWatchHistory();
    const watched = videoId ? isWatched(videoId) : false;

    return (
        <Card sx={{
            width: { xs: '100%', sm: '320px', md: '320px' },
            boxShadow: 'none',
            borderRadius: '12px',
            overflow: 'hidden',
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            transition: 'all 0.3s ease',
            '&:hover': {
                transform: 'translateY(-4px)',
                boxShadow: 'var(--card-hover-shadow)',
                borderColor: 'var(--primary-color)',
                '& .thumbnail': {
                    transform: 'scale(1.05)',
                }
            }
        }}>
            <Link to={videoId ? `/video/${videoId}` : demoVideoUrl}>
                <Box sx={{ position: 'relative', overflow: 'hidden' }}>
                    <CardMedia
                        className="thumbnail"
                        image={snippet?.thumbnails?.high?.url || demoThumbnailUrl}
                        alt={snippet?.title}
                        sx={{ 
                            width: '100%', 
                            height: 180,
                            transition: 'transform 0.5s ease',
                            ...(watched && {
                                opacity: 0.7,
                            })
                        }}
                    />
                    {contentDetails?.duration && (
                        <Typography
                            variant="caption"
                            sx={{
                                position: 'absolute',
                                bottom: 8,
                                right: 8,
                                bgcolor: 'rgba(0, 0, 0, 0.8)',
                                color: '#fff',
                                padding: '3px 6px',
                                borderRadius: '4px',
                                fontSize: '0.75rem',
                                fontWeight: '500'
                            }}
                        >
                            {contentDetails.duration}
                        </Typography>
                    )}
                    {watched && (
                        <Box
                            sx={{
                                position: 'absolute',
                                top: 8,
                                left: 8,
                                bgcolor: 'var(--primary-color)',
                                color: '#fff',
                                padding: '2px 6px',
                                borderRadius: '4px',
                                fontSize: '0.7rem',
                                fontWeight: '500',
                                opacity: 0.9
                            }}
                        >
                            Watched
                        </Box>
                    )}
                </Box>
            </Link>
            <CardContent sx={{
                backgroundColor: 'var(--card-bg)',
                padding: '12px',
                height: '106px',
            }}>
                <Link to={videoId ? `/video/${videoId}` : demoVideoUrl}>
                    <Typography 
                        variant='subtitle1' 
                        fontWeight='500' 
                        color='var(--text-primary)'
                        sx={{
                            lineHeight: '1.3',
                            marginBottom: '8px',
                            display: '-webkit-box',
                            overflow: 'hidden',
                            WebkitBoxOrient: 'vertical',
                            WebkitLineClamp: 2,
                            transition: 'color 0.2s ease',
                            '&:hover': {
                                color: 'var(--primary-color)',
                            },
                            ...(watched && {
                                color: 'var(--text-secondary)',
                            })
                        }}
                    >
                        {snippet?.title || demoVideoTitle}
                    </Typography>
                </Link>
                <Link to={snippet?.channelId ? `/channel/${snippet?.channelId}` : demoChannelUrl}>
                    <Typography 
                        variant='body2' 
                        fontWeight='400' 
                        color='var(--text-secondary)'
                        sx={{
                            display: 'flex',
                            alignItems: 'center',
                            marginTop: '4px',
                            transition: 'color 0.2s ease',
                            '&:hover': {
                                color: 'var(--primary-color)',
                            }
                        }}
                    >
                        {snippet?.channelTitle || demoChannelTitle}
                        <CheckCircle sx={{ fontSize: 12, color: 'var(--primary-color)', ml: '5px' }} />
                    </Typography>
                </Link>
                {statistics?.viewCount && (
                    <Typography 
                        variant="caption" 
                        sx={{ 
                            display: 'flex',
                            alignItems: 'center',
                            color: 'var(--text-secondary)',
                            mt: 1,
                            gap: '4px'
                        }}
                    >
                        <Visibility sx={{ fontSize: 14 }} />
                        {parseInt(statistics.viewCount).toLocaleString()} views
                    </Typography>
                )}
            </CardContent>
        </Card>
    );
};

export default VideoCard;
